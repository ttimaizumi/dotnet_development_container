


Run agent, opt
podman run -d  --name jenkins-agent  --network jenkins --replace \
    --restart=unless-stopped --security-opt label=disable --userns=keep-id \
    -v /run/user/1000/podman/podman.sock:/run/podman/podman.sock \
    -e CONTAINER_HOST=unix:///run/podman/podman.sock \
    jenkins_agent_img:latest \
    -url http://jenkins:8080 \
    -secret 'fd3c313cab499b60a5d169033b4ae90ed27ac58cb15d02a2a878cf2661aa4b3a' \
    -name podman-agent \
    -webSocket \
    -workDir /home/jenkins/agent
