
Enable podman service
``` bash
systemctl --user enable podman.service
```
Create jenkins network
```bash
podman network create jenkins

podman pull jenkins/jenkins:alpine

podman run -d --name jenkins --network jenkins --restart=unless-stopped -p 8080:8080 -p 50000:50000 -v jenkins_home:/var/jenkins_home jenkins:alpine
```
Admin password:
```bash
podman exec jenkins  cat /var/jenkins_home/secrets/initialAdminPassword
```
Build agent image
```bash
podman build . -f Containerfile.agen -t jenkins_agent_img
```

Run agent, opt
```bash
podman run -d  --name jenkins-agent  --network jenkins --replace \
    --restart=unless-stopped --security-opt label=disable --userns=keep-id \
    -v /run/user/1000/podman/podman.sock:/run/podman/podman.sock \
    -e CONTAINER_HOST=unix:///run/podman/podman.sock \
    jenkins_agent_img:latest \
    -url http://jenkins:8080 \
    -secret 'FROM_JENKINS_SERVER' \
    -name podman-agent \
    -webSocket \
    -workDir /home/jenkins/agent
```
```groovy

    pipeline {

    agent {
        label 'podman'
    }

    stages {

        stage('Environment') {
            steps {
                sh '''
                    id
                    podman version
                    podman info
                '''
            }
        }

        stage('Containers') {
            steps {
                sh '''
                    podman ps
                '''
            }
        }
    }
}
```
