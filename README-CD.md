## Part 1 - Script a Refresh

### EC2 Instance Details

To host the containerized web application reliably, an AWS EC2 instance was provisioned with a static Elastic IP so that automated deployment webhooks always have a consistent target address.

* **AMI Information:** Ubuntu Server 24.04 LTS (64-bit x86) — `ami-0c30b7300f5fb34cd` 
* **Instance Type:** `t2.medium` (2 vCPUs, 4 GB RAM)
* **Volume Size:** 30 GiB `gp3` root EBS volume
* **Elastic IP:** `3.84.105.167`

#### Security Group Configuration

| Type | Protocol | Port Range | Source | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| SSH | TCP | `22` | `130.108.0.0/16` | Administrative SSH access from Wright State University campus network |
| HTTP | TCP | `80` | `0.0.0.0/0` | Public web traffic to the hosted container application |
| Custom TCP | TCP | `9000` | `0.0.0.0/0` | Manual testing of the `webhook` listener endpoint and allows incoming webhook payloads from GitHub|

#### Security Group Justification

The inbound rules follow the principle of least privilege. SSH access (`22`) is restricted exclusively to my home IP address and the Wright State University CIDR block (`130.108.0.0/16`) rather than `0.0.0.0/0` to prevent unauthorized brute-force login attempts. HTTP traffic (`80`) is open to `0.0.0.0/0` so any user can view the live website in a browser. Finally, port `9000` (used by `adnanh/webhook`) is locked down to GitHub's official `hooks` IP ranges—retrieved from the GitHub Meta API—alongside my home IP for local testing, blocking unsolicited external traffic from hitting the deployment listener.

![EC2 Instance and Security Group](images/ec2-security-group.png)
*This screenshot confirms the `t2.medium` EC2 instance is running with an assigned Elastic IP and shows the configured Security Group inbound rules for ports 22, 80, and 9000.*

---

### Docker Setup on EC2 Instance

#### Installing Docker & Dependencies

On Ubuntu Server, Docker Engine and its required CLI/container runtime dependencies (`docker-ce`, `docker-ce-cli`, `containerd.io`, `docker-buildx-plugin`, and `docker-compose-plugin`) were installed using Docker's official convenience script after updating the system package index:

```bash
sudo apt update && sudo apt upgrade -y
curl -fsSL [https://get.docker.com](https://get.docker.com) -o get-docker.sh
sudo sh get-docker.sh
```

To allow the default ubuntu user to execute Docker commands without prepending sudo, the user was added to the docker group and the group membership was refreshed:

```
sudo usermod -aG docker ubuntu
newgrp docker
```

#### Confirming Docker Installation
Docker installation and daemon permissions were verified by checking the installed version and listing active containers without sudo:

```
docker --version
docker ps
```
![Docker installed & running](Images/docker-running.png)
*This screenshot proves Docker is installed and that the ubuntu user can run `docker ps` without requiring sudo privileges.*

### Testing on EC2 Instance
#### Pulling and Running the Container Image
Before automating deployments, the application image built in Project 6 was manually pulled from DockerHub and launched on the EC2 instance:

```
docker pull hayden445/ceg3120-project6:latest
docker run -d --name ceg3120-site -p 80:80 hayden445/ceg3120-project6:latest
```

#### `-it` vs. `-d` Flag Comparison
* `-it` **(Interactive + Pseudo-TTY):** Attaches the terminal's standard input and output directly to the container process. This is useful during initial debugging when inspecting live console output or running an interactive shell inside the container, but closing the SSH session or pressing `Ctrl+C`terminates the process.

* `-d` **(Detached Mode):**  Runs the container in the background as a daemon and returns control of the terminal prompt immediately.

* **Recommendation:** Once testing is complete, `-d` **(detached mode)** is strongly recommended because a production web server must continue running persistently in the background after the administrator disconnects from SSH.

#### Verifying the Web Application
After starting the container, `docker ps` was used to confirm the container status (Up) and port mapping (`0.0.0.0:80->80/tcp`). Navigating to `http://3.84.105.167` in a web browser verified that the web application rendered properly.

![Docker Hosting Website](Images/docker-website-running.png)

*This screenshot shows web browser loading the site at the EC2 instance's public Elastic IP.*

### Scripting Container Application Refresh
#### Bash Script Overview
To automate container updates whenever a new image is pushed to DockerHub, a Bash script was created at `~/scripts/refresh-container.sh` on the EC2 instance and saved in this repository at `deployment/refresh-container.sh`.

When executed, the script performs four sequential actions:

1. **Stop existing container:** Runs `docker stop ceg3120-site 2>/dev/null || true` to gracefully halt the active container without throwing a fatal error if no container is currently running.

2. **Remove old container:** Runs `docker rm ceg3120-site 2>/dev/null || true` to free up the container name and port binding.

3. **Pull updated image:** Runs `docker pull hayden445/ceg3120-project6:latest` to download the newest `latest` image tag from DockerHub.

4. **Launch updated container:** Runs 
`docker run -d --name ceg3120-site --restart unless-stopped -p 80:80 hayden445/ceg3120-project6:latest`
to start the updated container in detached mode with a restart policy that automatically brings the site back online if the Docker service or EC2 instance reboots.

### Testing & Verifying the Refresh Script
The script was made executable (`chmod +x ~/scripts/refresh-container.sh`) and verified in two stages:

1. Container Replacement Test: `docker ps` was run before and after executing `./refresh-container.sh` to confirm the old container was replaced by a brand-new `CONTAINER ID` running the `latest` image.

2. Reboot Persistence Test: The restart policy was inspected with `docker inspect --format '{{.HostConfig.RestartPolicy.Name}}' ceg3120-site` (returning `unless-stopped`), followed by `sudo reboot`. After reconnecting, `uptime` and `docker ps` confirmed the container restarted automatically on boot.

![Docker refresh-container.sh working](Images/docker-script-running.png)

*This screenshot shows `docker ps` before and after running `refresh-container.sh`, proving the script stops the old container and launches a new container ID with the latest image.*

![Reboot persistence](Images/docker-reboot-persistence.png)

*This screenshot confirms the container's restart policy is set to `unless-stopped` and shows `uptime` alongside `docker ps` after a system reboot, proving the container restarts automatically.*

## Part 2 - Listen

### Configuring a `webhook` Listener on EC2 Instance

#### Installing and Verifying `adnanh/webhook`

To enable the EC2 instance to listen for incoming deployment notifications from GitHub, `adnanh/webhook` was installed from Ubuntu's package repository:

```bash
sudo apt update
sudo apt install -y webhook
```

Successful installation was confirmed by checking the installed binary version(`2.8.0`)

```
webhook --version
```

#### Hook Definition File Summary
A hook configuration file was created at `/etc/webhook/hooks.json` on the EC2 instance and committed to this repository at `deployment/hooks.json`.

This file defines a single hook (`id: "redeploy-container"`) exposed at the endpoint `http://3.84.105.167:9000/hooks/redeploy-container` and performs the following:

* **Command Execution:** Runs `/home/ubuntu/scripts/refresh-container.sh` inside the `/home/ubuntu/scripts` working directory when triggered.

* **Trigger Rules (`and` logic):** All three conditions must evaluate to `true` before the script executes:

1. HMAC Signature Validation (`payload-hmac-sha256`): Validates the `X-Hub-Signature-256` HTTP header against the shared secret configured in GitHub, ensuring only authentic payloads signed by GitHub are accepted.

2. Action Status (`action == "completed"`): Ensures the hook ignores `requested` or `in_progress` workflow events and only evaluates finished workflow runs.

3. Workflow Conclusion (`workflow_run.conclusion == "success"`): Ensures the container is only refreshed after the GitHub Actions CI pipeline has succeeded and pushed the updated `latest` image to DockerHub.

#### Verifying Hook Loading and Payload Reception
To confirm `webhook` parses the JSON definition without syntax errors, the listener was launched manually in verbose mode:

```
webhook -hooks /etc/webhook/hooks.json -verbose
```

The console output confirmed `found 1 hook(s) in file` and `loaded: redeploy-container`.

![Webhook started and hook.js loaded](Images/webhook-started-hook-loaded.png)

*This screenshot shows `webhook` starting in verbose mode, confirming that `/etc/webhook/hooks.json` loaded cleanly and the `redeploy-container` endpoint is active.*

When testing live deliveries and monitoring `webhook` in production:

* **Monitoring `webhook` Logs:** Real-time logs from the background service are inspected using `sudo journalctl -u webhook.service -f` (or `sudo journalctl -u webhook.service -n 50`), which logs incoming HTTP requests, rule evaluation results (`matched` vs. `not matched`), and script execution output.

* **Inspecting `docker` Process Views:** Running `docker ps` before and after a webhook delivery confirms a successful deployment by displaying a newly generated `CONTAINER ID`, a reset `CREATED` / `STATUS` timestamp (`Up X seconds`), and the updated `hayden445/ceg3120-project6:latest` image.

### Configure a webhook Service on EC2 Instance
#### webhook Service File Summary
To ensure the webhook listener runs continuously in the background and starts automatically whenever the EC2 instance boots, a `systemd` unit file was created at `/etc/systemd/system/webhook.service` and saved in this repository at `deployment/webhook.service`.

* `[Unit]` Section: Defines the service description and uses `After=network.target docker.service` and `Requires=docker.service` so `webhook` waits until networking and the Docker daemon are online before starting.

* `[Service]` Section: Runs `/usr/bin/webhook -hooks /etc/webhook/hooks.json -verbose` under the `ubuntu` user and group (which have permissions to execute Docker commands without `sudo`) and sets `Restart=always` with `RestartSec=5` for automatic recovery.

* `[Install]` Section: Uses `WantedBy=multi-user.target` so `systemd` starts the service during normal multi-user system boot.

#### Enabling and Starting the `webhook` Service
After saving the unit file, `systemd` was reloaded, enabled for boot persistence, and started:

```
sudo systemctl daemon-reload
sudo systemctl enable webhook.service
sudo systemctl start webhook.service
```

#### Verifying Service Status and Script Execution
Running `sudo systemctl status webhook.service` verified that the service is both `enabled` and `active (running)`, including across system reboots. Combining `sudo journalctl -u webhook.service -f` with `docker ps` confirms that incoming valid payloads are captured by the `systemd` service and trigger `refresh-container.sh`.

![Webhook systemctl status](Images/webhook-systemctl.png)

*This screenshot shows `systemctl status webhook.service` reporting the service as `enabled` and `active (running)`.*



### Resources
* [Docker Post-Installation Steps for Linux](https://docs.docker.com/engine/install/linux-postinstall/): Used for adding the ubuntu user to the docker group to run Docker commands without sudo and configuring container restart policies (--restart unless-stopped).
* [Docker run CLI Reference](https://docs.docker.com/reference/cli/docker/container/run/): Referenced for comparing detached (-d) versus interactive (-it) container execution flags and port publishing (-p).
* [`adnanh/webhook` Repository](https://github.com/adnanh/webhook): Referenced for CLI flags (`-hooks`, `-verbose`) and webhook endpoint URL structure (`/hooks/{id}`).
* [`adnanh/webhook` Hook Rules Documentation](https://github.com/adnanh/webhook/blob/master/docs/Hook-Rules.md): Used to configure `and` trigger rules combining `payload-hmac-sha256` signature validation on `X-Hub-Signature-256` with JSON payload `value` matching.
* [Linux Handbook — How to Create a `systemd` Service](https://linuxhandbook.com/create-systemd-services/): Referenced for structuring `[Unit]`, `[Service]`, and `[Install]` sections and using `systemctl daemon-reload`, `enable`, and `start`.