## Part 1 - Containerizing the Web Application

### Web Content Overview
The web application hosted inside the container consists of static pages located in the [`web-content/`] (web-content/) directory:
* [`web-content/index.html`](web-content/index.html): The primary landing page for the site.
* [`web-content/about.html`](web-content/about.html): A secondary informational page.
* [`web-content/style.css`](web-content/style.css): The shared stylesheet providing layout styling and visual design across both HTML pages.

### Dockerfile Configuration
The container image is built using the project [`Dockerfile`](Dockerfile), which automates provisioning an Apache web server with the following directives:

```dockerfile
FROM httpd:2.4
COPY ./web-content/ /usr/local/apache2/htdocs/
```

* `FROM httpd:2.4`: Uses the official Apache HTTP Server version 2.4 image from Docker Hub a the lightweight base environment.
* `COPY ./web-content/ /usr/local/apache2/htdocs/`: Copies all local website files from the repository's `web-content/` folder directly into Apache's default document root directory (`/usr/local/apache2/htdocs/`), replacing the default server placeholder files.

### Building the Docker Image
To build the container image, run `docker build` from the repository root where the `Dockerfile` resides:
```
docker build -t hayden445/ceg3120-project6:latest .
```

* Docker Hub Tagging Requirements: When planning to publish to Docker Hub, the image tag passed to the `-t` flag must strictly follow the format `<dockerhub-username>/<repository-name>:<tag>`. Naming the image `hayden445/ceg3120-project6:latest` associates it directly with the destination account and repository namespace on Docker Hub.
* The trailing period (`.`) sets the build context to the current working directory so the `COPY` instruction correctly resolves the `./web-content/` folder path.

### Running the Container Locally
To instantiate a container from the built image and verify web traffic:
```
docker run -d --name ceg3120-web -p 8080:80 hayden445/ceg3120-project6:latest
```
* `-d`: Runs the container in detached mode (background).
* `--name ceg3120-web`: Assigns a recognizable container instance name for easy management.
* `-p 8080:80`: Maps port `8080` on the local host machine to port `80` (default HTTP port) inside the container.
* Once running, the site can be accessed in a web browser at `http://localhost:8080` for the home page and `http://localhost:8080/about.html` for the secondary page.

### Testing and Proof
The screenshot below demonstrates the container running locally via `docker ps` alongside browser windows validating that both `index.html` and `about.html` render properly with CSS styles applied:

Figure 1,2,and 3: Terminal output of docker ps showing the active container mapped to port 8080, and browser windows rendering both styled HTML pages.

![Terminal Output of docker ps](<Images/Screenshot 2026-11-09 183129.png>)
![Browser view of index.html](<Images/Screenshot 2026-11-09 183954.png>)
![Browser view of about.html](<Images/Screenshot 2026-11-09 184043.png>)

### Resources
* [Docker Hub httpd Official Image](https://hub.docker.com/_/httpd): Consulted to identify the official Apache 2.4 base image tag and locate the default document root directory (`/usr/local/apache2/htdocs/`).
* [Docker Build CLI Reference](https://docs.docker.com/reference/cli/docker/buildx/build/): Referenced for `docker build` syntax, context targeting, and `-t` tagging conventions for Docker Hub repositories.
* [Docker Hub Personal Access Token](https://docs.docker.com/security/for-developers/access-tokens/): Used to review requirements for generating scoped Personal Access Tokens for CLI authentication.