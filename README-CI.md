# Project 6 - Continuous Integration (CI) Pipeline

## Continuous Integration Project Overview

### Project Goal
The goal of this project is to design and automate a Continuous Integration (CI) pipeline that packages a static web application into an Apache HTTP Server (`httpd:2.4`) Docker container image and publishes versioned releases to Docker Hub. By leveraging Git semantic version tags (`vMAJOR.MINOR.PATCH`) alongside GitHub Actions, each tagged release automatically builds and pushes `latest`, `major`, and `major.minor` container image tags to Docker Hub, ensuring reproducible deployments and rollback capability without overwriting prior stable releases.

### Tools and Roles
* **Docker & Docker Desktop:** Used locally to build container images from a `Dockerfile`, test web application rendering across mapped ports, and verify rollback capability across distinct semantic version tags.
* **Git:** Used for local source version control, branching, and creating annotated semantic version tags (`git tag -a v*.*.*`) to mark release milestones.
* **GitHub (`ceg3120-cicd-godwin20-f26`):** Hosts the remote repository (`web-content/`, `Dockerfile`, and workflow definitions) and securely stores registry credentials via GitHub Actions Repository Secrets (`DOCKER_USERNAME` and `DOCKER_TOKEN`).
* **GitHub Actions (`.github/workflows/main.yml`):** Automates the CI pipeline on an `ubuntu-latest` runner whenever a semantic version tag (`v*.*.*`) is pushed, extracting tag metadata (`docker/metadata-action@v5`), authenticating with Docker Hub (`docker/login-action@v3`), and building/pushing multi-tagged images (`docker/build-push-action@v6`).
* **Docker Hub (`hayden445/ceg3120-project6`):** Serves as the public cloud container registry storing the published images and maintaining immutable `major.minor` tags alongside mutable `major` and `latest` pointers.

### CI Pipeline Architecture Diagram
The diagram below illustrates the end-to-end continuous integration workflow—from local code edits and semantic tagging through automated GitHub Actions execution to multi-tag image publishing on Docker Hub:

```mermaid
flowchart LR
    subgraph Local ["Local Development Environment"]
        A["Edit web-content/ & Commit"] --> B["Create Annotated Tag<br/>(git tag -a v1.1.0)"]
        B --> C["Push Tag to Origin<br/>(git push origin v1.1.0)"]
    end

    subgraph GitHub ["GitHub Repository (ceg3120-cicd-godwin20-f26)"]
        C --> D{"Tag Matches<br/>'v*.*.*'?"}
        D -- No --> E["Ignore (No Workflow Run)"]
        D -- Yes --> F["Trigger GitHub Actions<br/>(.github/workflows/main.yml)"]
        
        subgraph Runner ["GitHub Actions Runner (ubuntu-latest)"]
            F --> G["Checkout Code<br/>(actions/checkout@v4)"]
            G --> H["Authenticate via Secrets<br/>(docker/login-action@v3)"]
            H --> I["Extract SemVer Tags<br/>(docker/metadata-action@v5)"]
            I --> J["Build & Push Image<br/>(docker/build-push-action@v6)"]
        end
    end

    subgraph DockerHub ["Docker Hub (hayden445/ceg3120-project6)"]
        J --> K["Publish Image Tags:<br/>• :latest<br/>• :1 (major)<br/>• :1.1 (major.minor)"]
        K --> L["Prior Releases Preserved<br/>(e.g., :1.0 Available for Rollback)"]
    end
```

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



![Terminal Output of docker ps](<images/Screenshot 2026-11-09 183129.png>)
![Browser view of index.html](<images/Screenshot 2026-11-09 183954.png>)
![Browser view of about.html](<images/Screenshot 2026-11-09 184043.png>)

Figure 1,2,and 3: Terminal output of docker ps showing the active container mapped to port 8080, and browser windows rendering both styled HTML pages.

## Part 2 - Automating Builds with GitHub Actions and Docker Hub

### Configuring GitHub Repository Secrets
To authenticate automated builds with Docker Hub without hardcoding credentials in the repository, a scoped Personal Access Token (PAT) and GitHub Actions Secrets are used:

1. **Generating a Docker Hub PAT:**
   * In Docker Hub, navigate to **Account Settings** > **Personal access tokens** and select **Generate new token**.
   * **Recommended Scope:** Assign **Read & Write** permissions. This grants GitHub Actions the necessary privileges to read existing image manifests and push newly built container layers to the repository without exposing administrative or delete permissions.
2. **Adding Repository Secrets:**
   * In the GitHub repository, navigate to **Settings** > **Secrets and variables** > **Actions** and select **New repository secret**.
3. **Configured Secrets for This Project:**
   * `DOCKER_USERNAME`: Stores the Docker Hub account username (`hayden445`) used to identify the target registry namespace.
   * `DOCKER_TOKEN`: Stores the generated Read & Write Docker Hub Personal Access Token used to authenticate the CI runner session.

![GitHub Repository Secrets](images/repo-secrets.png)
*Figure 4: GitHub repository Actions secrets page confirming `DOCKER_USERNAME` and `DOCKER_TOKEN` are configured with masked values.*

---

### CI Workflow with GitHub Actions
The automated build pipeline is defined in the [Part 2 Workflow File](https://github.com/WSU-kduncan/ceg3120-cicd-godwin20-f26/blob/804cfd71f160a8c77151fce3e19d3aab4bf13e62/.github/workflows/main.yml) (linked via commit permalink prior to Part 3 modifications).

* **Workflow Trigger:**
  * Configured with `on: push: branches: [main]`. This ensures the pipeline executes automatically whenever a commit is pushed or merged into the `main` branch, while ignoring commits pushed to feature or testing branches.
* **Workflow Steps:**
  1. **Checkout Repository (`actions/checkout@v4`):** Clones the repository source files (`Dockerfile` and `web-content/`) onto the Ubuntu GitHub Actions runner so they are available in the build context.
  2. **Log in to Docker Hub (`docker/login-action@v3`):** Authenticates the runner with Docker Hub using `${{ secrets.DOCKER_USERNAME }}` and `${{ secrets.DOCKER_TOKEN }}`.
  3. **Build and Push Docker Image (`docker/build-push-action@v6`):** Builds the container image from the repository root context (`.`) and pushes it directly to Docker Hub tagged as `hayden445/ceg3120-project6:latest`.
* **Reusing This Workflow in Another Repository:**
  * **Changes in the Workflow File:** Update the `tags:` parameter inside `docker/build-push-action@v6` from `hayden445/ceg3120-project6:latest` to match the new destination `<dockerhub-username>/<repository-name>:latest`. If the target repository uses a different default branch name (such as `master`), update `branches:` under the `on: push:` trigger accordingly.
  * **Changes in the GitHub Repository:** Navigate to the new repository's **Settings** > **Secrets and variables** > **Actions** and add `DOCKER_USERNAME` and `DOCKER_TOKEN` secrets containing valid Docker Hub credentials.

---

### Testing and Validating the Pipeline
The automated CI pipeline is hosted at the [hayden445/ceg3120-project6 Docker Hub Repository](https://hub.docker.com/r/hayden445/ceg3120-project6).

1. **Verifying Workflow Execution:** Pushing a commit to `main` triggers the workflow under the repository's **Actions** tab, where each step can be inspected for successful execution and image push confirmation. Pushing to a separate branch verifies that non-`main` branches do not trigger builds.
2. **Verifying the Published Image:** After a successful workflow run, pulling the updated image (`docker pull hayden445/ceg3120-project6:latest`) and running a local container (`docker run -d -p 8080:80 hayden445/ceg3120-project6:latest`) confirms that changes committed to `main` are live in the published container.

![Main Branch Workflow Trigger](images/main-trigger.png)
*Figure 5: Successful GitHub Actions workflow run triggered by a commit pushed to the `main` branch, displaying the corresponding commit SHA.*

![Non-Main Branch Negative Test](images/branch-negative-test.png)
*Figure 6: A commit pushed to a non-`main` test branch alongside the Actions tab confirming no workflow execution was triggered.*

![Updated Image Browser Verification](images/change-to-image.png)
*Figure 7: Browser rendering updated site text after pushing changes to `main`, allowing GitHub Actions to rebuild the image, and running the newly pulled container locally.*



## Part 3 - Semantic Versioning

### Managing Git Tags
Semantic versioning (`vMAJOR.MINOR.PATCH`) is used to track container releases and prevent new builds from overwriting older working versions.
* **List existing tags:** `git tag -l` displays all tags currently stored in the local repository.
* **Create an annotated tag:** `git tag -a v1.0.0 -m "Release v1.0.0"` attaches a version tag with metadata to the most recent commit.
* **Push a tag to GitHub:** `git push origin v1.0.0` explicitly pushes the tag to the remote repository (standard `git push` commands only push branch commits).

### Semantic Versioning Workflow Configuration
The updated [GitHub Actions Workflow File](.github/workflows/docker-build.yml) automates multi-tag image publishing:
* **Workflow Trigger:** Configured with `on: push: tags: ['v*.*.*']`, removing the previous branch trigger so builds execute strictly when a semantic version tag is pushed.
* **Workflow Steps:**
  1. **Checkout Repository (`actions/checkout@v4`):** Checks out the tagged commit's source files onto the runner.
  2. **Log in to Docker Hub (`docker/login-action@v3`):** Authenticates with Docker Hub using `${{ secrets.DOCKER_USERNAME }}` and `${{ secrets.DOCKER_TOKEN }}`.
  3. **Extract Metadata (`docker/metadata-action@v5`):** Parses the pushed Git tag (e.g., `v1.1.0`) to automatically generate `latest`, `major` (`1`), and `major.minor` (`1.1`) Docker image tags.
  4. **Build and Push (`docker/build-push-action@v6`):** Builds the container image and pushes all three generated tags to `hayden445/ceg3120-project6`.
* **Reusing This Workflow in Another Repository:**
  * **Changes in the Workflow File:** Update the `images:` field inside `docker/metadata-action@v5` from `hayden445/ceg3120-project6` to the target `<dockerhub-username>/<repository-name>`.
  * **Changes in the GitHub Repository:** Add `DOCKER_USERNAME` and `DOCKER_TOKEN` under **Settings** > **Secrets and variables** > **Actions** in the destination repository.

### Testing and Validating Semantic Releases
Published tags and digests are available in the [hayden445/ceg3120-project6 Docker Hub Tags Page](https://hub.docker.com/r/hayden445/ceg3120-project6/tags).

![Tag Workflow Trigger](images/tag-trigger.png)
*Figure 8: Terminal output from `git tag -l` alongside the GitHub Actions run triggered by pushing the `v1.0.0` tag.*

![Untagged Commit Negative Test](images/tag-negative-test.png)
*Figure 9: A commit pushed to `main` without a tag alongside the Actions tab confirming no workflow was triggered.*

![Docker Hub Semantic Tag Set](images/tag-set.png)
*Figure 10: Docker Hub repository showing `latest`, `1`, `1.1`, and `1.0` tags generated automatically.*

![Two Releases Digest Comparison](images/two_releases.png)
*Figure 11: Docker Hub image digests showing `latest` and `1` updated to the new `1.1` digest while `1.0` remained pinned to the original image.*

![Version Rollback Verification](images/rollback-proof.png)
*Figure 12: Side-by-side browser windows running `:1.0` on port 8081 and `:1.1` on port 8082, verifying rollback capability between releases.*



### Resources
* [Docker Hub httpd Official Image](https://hub.docker.com/_/httpd): Consulted to identify the official Apache 2.4 base image tag and locate the default document root directory (`/usr/local/apache2/htdocs/`).
* [Docker Build CLI Reference](https://docs.docker.com/reference/cli/docker/buildx/build/): Referenced for `docker build` syntax, context targeting, and `-t` tagging conventions for Docker Hub repositories.
* [Docker Hub Personal Access Token](https://docs.docker.com/security/for-developers/access-tokens/): Used to review requirements for generating scoped Personal Access Tokens for CLI authentication.
* [Docker Docs: CI/CD with GitHub Actions](https://docs.docker.com/build/ci/github-actions/): Referenced to structure the automated Docker build and push pipeline using official Docker GitHub Actions.
* [GitHub Docs: Publishing Docker Images](https://docs.github.com/en/actions/tutorials/publish-packages/publish-docker-images): Consulted for configuring repository secrets (`DOCKER_USERNAME` and `DOCKER_TOKEN`) and restricting workflow triggers to the `main` branch.
* [Semantic Versioning 2.0.0](https://semver.org/): Referenced for `vMAJOR.MINOR.PATCH` version numbering conventions.
* [GitHub - docker/metadata-action](https://github.com/docker/metadata-action?tab=readme-ov-file): Used to configure `semver` tag extraction patterns (`{{major}}` and `{{major}}.{{minor}}`) and `latest` tagging.
* [GitHub - Markdown Mermaid Diagrams](https://github.blog/developer-skills/github/include-diagrams-markdown-files-mermaid/): Referenced to format `mermaid` fenced code blocks so the CI pipeline architecture diagram renders natively inside `README-CI.md` on GitHub.
* [Mermaid Syntax](https://mermaid.js.org/syntax/flowchart.html): Consulted for `flowchart LR` directional syntax, `subgraph` container grouping (Local, GitHub, and Docker Hub environments), and conditional decision node branching.