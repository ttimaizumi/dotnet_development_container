# Incremental Jenkins Pipeline Activities

Each activity leaves the `Jenkinsfile` in a working state. Students should commit the result
before moving to the next activity so they can compare the pipeline's evolution and recover
easily.

## Prerequisites

Prepare these before starting the Jenkinsfile exercises:

- The Jenkins controller container is running.
- The Jenkins build agent container is connected with the label `build-agent`.
- The build agent contains .NET 10, Git, and the Podman client.
- A separate Jenkins deployment agent container is connected with the label `deploy-agent`.
- The deployment agent contains Git, `kubectl`, and `curl`.
- The local registry is available at `localhost:5000`.
- The three kind clusters exist: `kind-dev`, `kind-qa`, and `kind-prd`.
- Kubernetes manifests and Kustomize overlays exist.
- Jenkins can read the GitHub repository.
- The deployment agent has read-only access to the kubeconfig file and network access to the
  Kubernetes API servers. The credentials in that file must permit the required deployments.
- The build agent has access to the rootless Podman socket.

### Configure Jenkins nodes

Create the build and deployment nodes before starting their agent containers:

1. From the Jenkins dashboard, select **Manage Jenkins** -> **Nodes** -> **New Node**.
2. Enter `build-agent` as the node name, select **Permanent Agent**, and create the node.
3. Set **Remote root directory** to `/home/jenkins/agent` and **Labels** to `build-agent`.
4. Set **Usage** to **Only build jobs with label expressions matching this node**.
5. Set **Launch method** to **Launch agents by connecting it to the controller**, then save.
6. Repeat the process with node name and label `deploy-agent`. Use the same remote root,
   usage, and launch method.
7. Open each node's status page and keep its inbound-agent secret available for the corresponding
   `podman run` command below. Each node has a different secret.

To obtain the value for `FROM_JENKINS_SERVER`:

1. From the Jenkins dashboard, select **Manage Jenkins** -> **Nodes**.
2. Select the node that will connect, such as `build-agent` or `deploy-agent`.
3. Open the node's status page. While the node is offline, Jenkins displays instructions for
   launching an inbound agent.
4. Find the generated agent command and copy the token immediately following `-secret`. Use that
   token in place of `FROM_JENKINS_SERVER` in the matching `podman run` command.
5. Repeat these steps for the other node. Secrets are node-specific, so do not reuse the build
   agent's secret for the deployment agent or commit either secret to the repository.

### Start the build agent

The image extends the Jenkins inbound agent and includes the .NET 10 SDK, Git, and the Podman
client. The Podman client uses the host's rootless Podman API socket; it does not run a separate
container engine inside the agent.

The build node must have these settings:

- Node name: `build-agent`
- Label: `build-agent`
- Remote root directory: `/home/jenkins/agent`
- Launch method: inbound agent

Copy the node's secret from Jenkins, make sure the `jenkins` Podman network exists, and start the
agent as the host user that owns the rootless Podman socket:

Compile the build agent image:

```bash
podman build -f Container.build-agent -t build-agent-img
```

Then start the Jenkins build agent:

```bash
podman run -d \
    --name build-agent \
    --network jenkins \
    --replace \
    --restart=unless-stopped \
    --security-opt label=disable \
    --userns=keep-id \
    -v "$XDG_RUNTIME_DIR/podman/podman.sock:/run/podman/podman.sock" \
    -e CONTAINER_HOST=unix:///run/podman/podman.sock \
    build-agent-img:latest \
    -url http://jenkins:8080 \
    -secret 'FROM_JENKINS_SERVER' \
    -name build-agent \
    -webSocket \
    -workDir /home/jenkins/agent
```

Replace `FROM_JENKINS_SERVER` with the inbound-agent secret shown by Jenkins. 

In Jenkins, wait for `build-agent` to report as online and confirm that it retains the
`build-agent` label. The pipeline selects the label, not the node name.

### Start the deployment agent

Build the deployment image from the repository root:

```bash
podman build \
  --file Containerfile.deploy-agent \
  --tag deploy-agent-img:latest \
  .
```

The image extends the Jenkins inbound agent and includes Git, `curl`, and `kubectl` v1.36.3
with its built-in Kustomize support. It intentionally does not include Podman or `kind`.

The deployment node must have these settings:

- Node name: `deploy-agent`
- Label: `deploy-agent`
- Remote root directory: `/home/jenkins/agent`
- Launch method: inbound agent

Copy this node's secret from Jenkins and start the agent with a read-only kubeconfig:

```bash
podman run -d \
  --name deploy-agent \
  --network jenkins \
  --replace \
  --restart=unless-stopped \
  --security-opt label=disable \
  --userns=keep-id \
  -v "$HOME/.kube/config:/home/jenkins/kubeconfig:ro" \
  -e KUBECONFIG=/home/jenkins/kubeconfig \
  deploy-agent-img:latest \
  -url http://jenkins:8080 \
  -secret 'FROM_JENKINS_SERVER' \
  -name deploy-agent \
  -webSocket \
  -workDir /home/jenkins/agent
```

Replace `FROM_JENKINS_SERVER` with the secret for the deployment node. The kubeconfig must use
Kubernetes API server addresses that are reachable from the `jenkins` Podman network; a server
address such as `127.0.0.1` refers to the deployment-agent container itself and will not reach a
host-published API server. Keep the mount read-only and grant its credentials only the permissions
required by the deployment scripts.

In Jenkins, wait for `deploy-agent` to report as online and confirm that it retains the
`deploy-agent` label.

If $HOME/.kube/config is missing then create
```bash 
mkdir -p $HOME/.kube/config
```

### Start the local registry

Run a local OCI registry before starting the pipeline. The named volume preserves images when
the registry container is replaced or restarted:

```bash
podman run -d \
  --name registry \
  --network jenkins \
  --replace \
  --restart=unless-stopped \
  -p 5000:5000 \
  -v registry-data:/var/lib/registry \
  docker.io/library/registry:3
```

Verify that the Registry API is available from the host:

```bash
curl http://localhost:5000/v2/
```

A successful request returns `{}`. This registry uses HTTP rather than TLS, so pipeline pushes
must use `podman push --tls-verify=false`. Do not expose this development registry outside the
local environment.

Keep infrastructure creation outside the application pipeline. The pipeline should consume
existing Jenkins, registry, and kind infrastructure.

The build agent does not need `kubectl` or the `kind` CLI. The deployment agent does not need
Podman or the `kind` CLI: it uses `kubectl` to modify clusters that already exist and references
images already published to the registry.

## Activity 1: First Pipeline

**Goal:** Understand Jenkins declarative pipeline structure and confirm both agents work.

Create the initial `Jenkinsfile`:

```groovy
pipeline {
    agent {
        label 'build-agent'
    }

    stages {
        stage('Build Environment') {
            steps {
                sh '''
                    dotnet --info
                '''
            }
        }

        stage('Deployment Environment') {
            agent {
                label 'deploy-agent'
            }
            steps {
                sh '''
                    git --version
                    kubectl version --client
                    curl --version
                '''
            }
        }
    }
}
```

### Student Tasks

1. Add the `Jenkinsfile`.
2. Commit and push it.
3. Trigger the Jenkins job.
4. Confirm that each stage runs in the expected container.
5. Locate the stage logs and the separate agent workspaces.
6. Deliberately change one agent label and observe the queued build.
7. Restore the correct label.

### Success Criteria

- Jenkins assigns build work to `build-agent` and deployment work to `deploy-agent`.
- Each agent has the command-line tools required for its responsibility.
- The pipeline appears in Stage View.

### Concepts

- Pipeline as code
- Controller versus agent
- Stage-level agent selection
- Jenkins workspace
- Declarative pipeline syntax

---

## Activity 2: Checkout and Build

**Goal:** Turn the pipeline into basic continuous integration.

Add global options and environment information:

```groovy
pipeline {
    agent {
        label 'build-agent'
    }

    environment {
        CONFIGURATION = 'Release'
        REPOSITORY_URL = 'https://github.com/OWNER/REPOSITORY.git'
        REPOSITORY_BRANCH = 'main'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout([
                    $class: 'GitSCM',
                    branches: [[name: "*/${env.REPOSITORY_BRANCH}"]],
                    extensions: [],
                    userRemoteConfigs: [[
                        credentialsId: 'github-credentials',
                        url: env.REPOSITORY_URL
                    ]]
                ])
                sh 'git log -1 --oneline'
            }
        }

        stage('Build') {
            steps {
                sh '''
                    dotnet restore
                    dotnet build --configuration "$CONFIGURATION" --no-restore
                '''
            }
        }
    }
}
```

Replace `OWNER/REPOSITORY` with the GitHub repository path. Create a Jenkins username/password
credential named `github-credentials` for a private repository. For a public repository, remove
the `credentialsId` line. `skipDefaultCheckout(true)` ensures Jenkins does not perform a second,
implicit checkout when the job itself is loaded from SCM.

### Student Tasks

1. Set the repository URL, branch, and credentials ID.
2. Add checkout and build stages.
3. Introduce a compilation error.
4. Observe that later stages do not execute.
5. Correct the error and rerun the pipeline.

### Success Criteria

- Jenkins checks out the expected commit.
- The Release build succeeds.
- Compilation failures stop the pipeline.

### Concepts

- CI feedback
- Fail-fast behavior
- Reproducible build configuration
- Why concurrent deployments should be disabled

---

## Activity 3: Automated Tests

**Goal:** Use test results as a quality gate.

Add a test stage:

```groovy
stage('Unit Test') {
    steps {
        sh '''
            rm -rf TestResults
            dotnet test \
                --configuration "$CONFIGURATION" \
                --no-build \
                --logger "trx;LogFileName=unit-tests.trx" \
                --results-directory TestResults
        '''
    }
    post {
        always {
            archiveArtifacts artifacts: 'TestResults/**/*',
                             allowEmptyArchive: true
        }
    }
}
```

Install and configure a TRX-compatible test reporting plugin if test results should appear as
Jenkins test reports. Otherwise, archive the TRX files for this initial exercise.

### Student Tasks

1. Add one passing unit test.
2. Add one deliberately failing test.
3. Observe the stage and pipeline result.
4. Fix the test.
5. Inspect the archived test artifact.

### Success Criteria

- Tests run after compilation.
- A failed test prevents image packaging.
- Test output remains available after the build.

### Concepts

- Quality gates
- Test result publishing
- The difference between build artifacts and test reports
- Using `post { always { ... } }`

---

## Activity 4: Identify the Release Artifact

**Goal:** Give every build an immutable, traceable identity.

Add environment initialization:

```groovy
environment {
    CONFIGURATION = 'Release'
    REGISTRY = 'localhost:5000'
    IMAGE_NAME = 'minimal-api'
}
```

Add a stage that derives the image tag:

```groovy
stage('Version') {
    steps {
        script {
            env.SHORT_COMMIT = sh(
                script: 'git rev-parse --short=7 HEAD',
                returnStdout: true
            ).trim()

            env.IMAGE_TAG = "git-${env.SHORT_COMMIT}"
            env.IMAGE = "${env.REGISTRY}/${env.IMAGE_NAME}:${env.IMAGE_TAG}"
        }

        echo "Release image: ${env.IMAGE}"
    }
}
```

### Student Tasks

1. Compare the Jenkins build number with the Git commit SHA.
2. Trigger two builds from the same commit.
3. Confirm that both builds identify the same source version.
4. Explain why `latest` is unsuitable for promotion.

### Success Criteria

The pipeline produces an image name such as:

```text
localhost:5000/minimal-api:git-a1b2c3d
```

### Concepts

- Traceability
- Immutable artifact naming
- Git SHA versus build number
- Build once, promote many

---

## Activity 5: Package and Publish the Image

**Goal:** Produce the deployable artifact and push it to the local registry.

Add a package stage using the .NET OCI publishing mechanism:

```groovy
stage('Package Image') {
    steps {
        sh '''
            rm -rf out
            mkdir -p out

            dotnet publish src/Api \
                --configuration "$CONFIGURATION" \
                --no-build \
                -p:PublishProfile=DefaultContainer \
                -p:ContainerRepository="$IMAGE_NAME" \
                -p:ContainerImageTag="$IMAGE_TAG" \
                -p:ContainerArchiveOutputPath="$WORKSPACE/out/minimal-api.tar"

            podman load --input out/minimal-api.tar
            podman tag "$IMAGE_NAME:$IMAGE_TAG" "$IMAGE"
        '''
    }
}
```

Add registry publication:

```groovy
stage('Publish Image') {
    steps {
        sh '''
            podman push --tls-verify=false "$IMAGE"
            podman image inspect "$IMAGE"
        '''
    }
}
```

### Student Tasks

1. Run the pipeline.
2. Query the local registry catalog.
3. Confirm that the Git SHA tag exists.
4. Compare the source commit with the image tag.
5. Attempt to publish while the registry is stopped.
6. Restart the registry and retry the failed stage or build.

### Success Criteria

- The image is built only after tests pass.
- The registry contains the commit-tagged image.
- No `latest` tag is created.

### Concepts

- Build artifacts
- Local registries
- OCI images
- Why packaging follows testing
- Difference between image creation and deployment

---

### Prepare the development kind cluster

Run these commands on the host, not on a Jenkins agent. Install `kind` with Go and make the
resulting binary available in the current shell:

```bash
go install sigs.k8s.io/kind@latest
export PATH="$(go env GOPATH)/bin:$PATH"
kind version
```

Create the development cluster. The name `dev` produces the `kind-dev` context used by the
deployment script:

```bash
kind create cluster --name dev
kubectl cluster-info --context kind-dev
```

If `kind-dev` already exists, verify it with `kind get clusters` instead of creating it again.

---

## Activity 6: Deploy Automatically to Development

**Goal:** Introduce continuous deployment to the first environment.

First create a deployment script with a stable interface:

```text
./scripts/deploy.sh <context> <overlay> <image>
```

Create `scripts/deploy.sh` with the following content:

```bash
#!/usr/bin/env bash

set -euo pipefail

if [ "$#" -ne 3 ]; then
    echo "Usage: $0 <context> <overlay> <image>" >&2
    exit 2
fi

CONTEXT="$1"
OVERLAY="$2"
IMAGE="$3"
NAMESPACE="minimal-api"
OVERLAY_PATH="k8s/overlays/$OVERLAY"
MIGRATION_JOB="migration"

if [ ! -d "$OVERLAY_PATH" ]; then
    echo "Kustomize overlay not found: $OVERLAY_PATH" >&2
    exit 1
fi

if ! kubectl config get-contexts "$CONTEXT" >/dev/null 2>&1; then
    echo "Kubernetes context not found: $CONTEXT" >&2
    exit 1
fi

kubectl --context "$CONTEXT" get --raw=/readyz >/dev/null
kubectl --context "$CONTEXT" apply -k "$OVERLAY_PATH"
kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    set image deployment/api api="$IMAGE"

# Recreate the Job so migrations run for every deployment.
kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    delete job "$MIGRATION_JOB" --ignore-not-found --wait=true
kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    create job "$MIGRATION_JOB" --image="$IMAGE" -- migrate

if ! kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    wait --for=condition=complete --timeout=180s "job/$MIGRATION_JOB"; then
    kubectl --context "$CONTEXT" -n "$NAMESPACE" \
        logs "job/$MIGRATION_JOB" --all-containers=true || true
    exit 1
fi

kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    logs "job/$MIGRATION_JOB" --all-containers=true
kubectl --context "$CONTEXT" -n "$NAMESPACE" \
    rollout status deployment/api --timeout=180s
```

Make the script executable and commit that permission to Git:

```bash
chmod +x scripts/deploy.sh
```

This example assumes the application image accepts `migrate` as its migration command. Change the
arguments after `--image="$IMAGE" --` if the application exposes migrations differently.

Then add the development deployment:

```groovy
stage('Deploy Dev') {
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh '''
            ./scripts/deploy.sh \
                kind-dev \
                dev \
                "$IMAGE"
        '''
    }
}
```

The explicit checkout is required because `deploy-agent` has a separate workspace from the
build agent. It provides the deployment script and Kubernetes manifests at the same Git revision
that produced the image.

The script should:

1. Select and verify `kind-dev`.
2. Apply the dev Kustomize overlay.
3. Configure the workload to use `$IMAGE`.
4. Run the migration Job.
5. Wait for the migration to succeed.
6. Wait for the API rollout.

Do not put all deployment commands directly in the `Jenkinsfile`. The Jenkinsfile should
express pipeline orchestration while the script handles Kubernetes mechanics.

### Student Tasks

1. Deploy the image to development.
2. Use `kubectl` to inspect the Deployment and pods.
3. Confirm the running image tag matches the Git commit.
4. Introduce an invalid readiness probe.
5. Observe Jenkins waiting for and eventually rejecting the rollout.
6. Restore the correct probe.

### Success Criteria

- A successful main-branch build deploys to `kind-dev`.
- Jenkins waits for rollout completion.
- A failed rollout fails the pipeline.

### Concepts

- Continuous deployment
- Kubernetes contexts
- Deployment status
- Database migrations
- Separating pipeline logic from deployment logic

---

## Activity 7: Development Smoke Test

**Goal:** Verify behavior after deployment rather than trusting rollout status alone.

Add a smoke-test stage:

```groovy
stage('Test Dev') {
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh '''
            ./scripts/smoke-test.sh http://localhost:8081
        '''
    }
}
```

The initial smoke test should verify:

- `/health/ready` returns HTTP 200.
- A todo can be created.
- The created todo can be retrieved.
- The response contains the expected data.

### Student Tasks

1. Implement the basic health check.
2. Add an API write/read test.
3. Make the application return an incorrect response while keeping its readiness endpoint
   healthy.
4. Confirm the smoke test catches the behavioral regression.

### Success Criteria

Development promotion stops when runtime behavior is incorrect.

### Concepts

- Deployment success versus application success
- Smoke tests
- Integration testing
- Test data cleanup

---

## Activity 8: Promote the Artifact to QA

**Goal:** Promote the already-built image without rebuilding it.

Add QA deployment and testing:

```groovy
stage('Deploy QA') {
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh '''
            ./scripts/deploy.sh \
                kind-qa \
                qa \
                "$IMAGE"
        '''
    }
}

stage('Test QA') {
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh '''
            ./scripts/smoke-test.sh http://localhost:8082
        '''
    }
}
```

Add a verification step to the deployment script that prints the deployed image:

```bash
kubectl \
    --context "$CONTEXT" \
    -n minimal-api \
    get deployment api \
    -o jsonpath='{.spec.template.spec.containers[0].image}'
```

### Student Tasks

1. Record the image used in development.
2. Deploy to QA.
3. Confirm QA uses the identical tag.
4. Confirm the package stage ran only once.
5. Add a QA-only configuration difference through the QA overlay.
6. Cause the QA test to fail and confirm production is not offered.

### Success Criteria

- QA receives exactly the image tested in development.
- No rebuild occurs between environments.
- Failed QA tests stop promotion.

### Concepts

- Artifact promotion
- Environment-specific configuration
- Separation of artifact and configuration
- QA as a deployment gate

---

## Activity 9: Add Production Approval

**Goal:** Introduce a human-controlled production gate.

Add an approval stage:

```groovy
stage('Approve Production') {
    options {
        timeout(time: 10, unit: 'MINUTES')
    }

    input {
        message "Deploy ${IMAGE} to production?"
        ok 'Deploy'
    }

    steps {
        echo 'Production deployment approved'
    }
}
```

Then add production deployment:

```groovy
stage('Deploy Production') {
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh '''
            ./scripts/deploy.sh \
                kind-prd \
                prd \
                "$IMAGE"
        '''
    }
}

stage('Verify Production') {
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh '''
            ./scripts/smoke-test.sh \
                http://localhost:8083 \
                --read-only
        '''
    }
}
```

The production smoke test should preferably be read-only or use temporary data that it cleans
up.

### Student Tasks

1. Run the pipeline up to the approval.
2. Inspect dev and QA before approving.
3. Reject one deployment.
4. Run it again and approve.
5. Confirm production uses the same image as dev and QA.
6. Let one approval expire to demonstrate timeout behavior.

### Success Criteria

- Production cannot deploy before dev and QA succeed.
- Rejection does not modify production.
- Approval deploys the same immutable artifact.

### Concepts

- Manual gates
- Separation of duties
- Approval timeout
- Production verification

---

## Activity 10: Branch and Pull Request Behavior

**Goal:** Separate continuous integration from environment delivery.

Add a condition to deployment stages:

```groovy
stage('Deploy Dev') {
    when {
        branch 'main'
    }
    agent {
        label 'deploy-agent'
    }
    steps {
        checkout scm
        sh './scripts/deploy.sh kind-dev dev "$IMAGE"'
    }
}
```

Apply the same condition to all environment stages.

The resulting behavior should be:

| Event | Build | Unit tests | Package | Deploy |
|---|---:|---:|---:|---:|
| Pull request | Yes | Yes | Optional | No |
| Feature branch | Yes | Yes | Optional | No |
| `main` branch | Yes | Yes | Yes | Dev -> QA -> approval -> production |

If package creation is not needed for pull requests, place a `when` condition on the package
and publish stages as well.

### Student Tasks

1. Open a pull request.
2. Confirm build and test stages execute.
3. Confirm no cluster is modified.
4. Merge the pull request.
5. Confirm the main pipeline starts deployment.

### Success Criteria

Unmerged code cannot reach shared environments.

### Concepts

- Multibranch pipelines
- Pull request validation
- Branch conditions
- Protecting shared environments

---

## Activity 11: Pipeline Cleanup and Reporting

**Goal:** Make the pipeline usable repeatedly.

Add top-level post actions:

```groovy
post {
    success {
        echo "Successfully promoted ${IMAGE}"
    }

    unsuccessful {
        echo "Pipeline failed for ${env.GIT_COMMIT}"
    }

    always {
        archiveArtifacts artifacts: 'TestResults/**/*',
                         allowEmptyArchive: true
        cleanWs()
    }
}
```

Depending on the installed plugins, `cleanWs()` may require the Workspace Cleanup plugin.
Otherwise, use controlled shell cleanup.

Add a deployment summary containing:

- Git commit
- Image tag
- Jenkins build URL
- Dev result
- QA result
- Production result

### Student Tasks

1. Identify files that should persist after the build.
2. Ensure test reports remain available.
3. Ensure temporary image archives are removed.
4. Rerun the pipeline and confirm stale files do not affect it.

### Success Criteria

Pipeline runs are isolated and retain useful evidence.

### Concepts

- Post-build actions
- Artifact retention
- Workspace cleanup
- Auditability

---

## Activity 12: Failure and Recovery Exercise

**Goal:** Demonstrate how the pipeline reacts to realistic failures.

Assign each group one failure:

- Unit test failure
- Registry unavailable
- Development migration failure
- Readiness probe failure
- QA acceptance test failure
- Production approval rejection
- Production rollout failure

For each failure, students document:

1. Which stage failed.
2. Which environments were modified.
3. Whether the artifact remains usable.
4. How to retry safely.
5. Whether rollback is required.

Then add an explicit production rollback exercise:

```bash
kubectl \
    --context kind-prd \
    -n minimal-api \
    rollout undo deployment/api
```

Explain that rolling back the application does not necessarily reverse a database migration.

---

## Final Jenkinsfile Shape

By the final activity, the pipeline should have this structure:

```groovy
pipeline {
    agent {
        label 'build-agent'
    }

    options {
        timestamps()
        disableConcurrentBuilds()
    }

    environment {
        CONFIGURATION = 'Release'
        REGISTRY = 'localhost:5000'
        IMAGE_NAME = 'minimal-api'
    }

    stages {
        stage('Checkout') {
            // Checkout and identify commit
        }

        stage('Build') {
            // Restore and compile
        }

        stage('Unit Test') {
            // Run and publish tests
        }

        stage('Version') {
            // Create immutable Git SHA image tag
        }

        stage('Package Image') {
            // Publish OCI image
        }

        stage('Publish Image') {
            // Push once to local registry
        }

        stage('Deploy Dev') {
            agent {
                label 'deploy-agent'
            }
            // Checkout and deploy automatically
        }

        stage('Test Dev') {
            agent {
                label 'deploy-agent'
            }
            // Checkout and run integration tests
        }

        stage('Deploy QA') {
            agent {
                label 'deploy-agent'
            }
            // Checkout and promote the same image
        }

        stage('Test QA') {
            agent {
                label 'deploy-agent'
            }
            // Checkout and run acceptance tests
        }

        stage('Approve Production') {
            // Human approval
        }

        stage('Deploy Production') {
            agent {
                label 'deploy-agent'
            }
            // Checkout and promote the same image
        }

        stage('Verify Production') {
            agent {
                label 'deploy-agent'
            }
            // Checkout and run the read-only smoke test
        }
    }

    post {
        // Reports, status, and cleanup
    }
}
```

The top-level `build-agent` remains the default for checkout, compilation, testing,
packaging, and registry publication. Each deployment or environment test stage overrides that
default with `deploy-agent`. Because the two containers do not share a Jenkins workspace, every
stage on `deploy-agent` checks out the pipeline's SCM revision before invoking repository scripts.

## Suggested Class Schedule

| Session | Activities | Outcome |
|---|---|---|
| 1 | 1-3 | Working CI pipeline |
| 2 | 4-5 | Immutable image published locally |
| 3 | 6-7 | Automated development deployment |
| 4 | 8-9 | QA promotion and production approval |
| 5 | 10-12 | Pull requests, reporting, and recovery |

The teaching progression is:

```text
Execute
-> Build
-> Test
-> Package
-> Publish
-> Deploy
-> Verify
-> Promote
-> Approve
-> Operate
```
