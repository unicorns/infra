FROM registry.k8s.io/kubectl:v1.34.8 AS kubectl

# This stage is used to keep the cache valid across different systems (even when the file permissions change).
# Use this stage as a courier to copy files from the build context to the image.
# Derived from:
# https://github.com/devcontainers/cli/issues/153#issuecomment-1278293424
FROM scratch AS courier

COPY --chmod=400 requirements.txt /

FROM debian:bookworm-20231030-slim

SHELL ["/bin/bash", "-c"]
# We are using docker. To keep things simple we won't use venv
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# Install requirements
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl git jq openssh-client python3-pip unzip wget \
    && rm -rf /var/lib/apt/lists/*

ARG TERRAFORM_VERSION=1.8.2
RUN wget --quiet "https://releases.hashicorp.com/terraform/${TERRAFORM_VERSION}/terraform_${TERRAFORM_VERSION}_linux_amd64.zip" -O /tmp/terraform.zip \
    && echo "74f3cc4151e52d94e0ecbe900552adc9b8440b4a8dc12f7fdaab2d0280788acc /tmp/terraform.zip" | sha256sum -c - \
    && unzip /tmp/terraform.zip -d /usr/local/bin terraform \
    && rm /tmp/terraform.zip

ARG TERRAGRUNT_VERSION=0.53.8
RUN wget --quiet "https://github.com/gruntwork-io/terragrunt/releases/download/v${TERRAGRUNT_VERSION}/terragrunt_linux_amd64" -O /usr/local/bin/terragrunt \
    && echo "d20345f13c99decbc6018fd836c06fa6a5d4b505d19b04db1138665126df67b5 /usr/local/bin/terragrunt" | sha256sum -c - \
    && chmod +x /usr/local/bin/terragrunt

# Install yq
ARG YQ_VERSION=4.34.1
RUN wget --quiet https://github.com/mikefarah/yq/releases/download/v${YQ_VERSION}/yq_linux_amd64 -O /usr/bin/yq \
    && echo "7b0fdb1137ae8b80b79610d0046aa42e9a2a7df5eee25dc41ec81a736bb93935ec179b1763b7bcd95af6fa9409d46192f14e85384c165a7c9f70e3159e4dcbae /usr/bin/yq" | sha512sum -c - \
    && chmod +x /usr/bin/yq

# Install Python dependencies
COPY --from=courier /requirements.txt /tmp/
RUN python3 -m pip install -r /tmp/requirements.txt && rm /tmp/requirements.txt

# Install kubectl
COPY --from=kubectl /bin/kubectl /usr/local/bin/

ARG KUBELOGIN_VERSION=0.2.19
RUN wget --quiet "https://github.com/Azure/kubelogin/releases/download/v${KUBELOGIN_VERSION}/kubelogin-linux-amd64.zip" -O /tmp/kubelogin.zip \
    && echo "ebaeff02aa899c5cae6a2b954b64fc02738185319df2570f7dc053451efa4b2f  /tmp/kubelogin.zip" | sha256sum -c - \
    && unzip /tmp/kubelogin.zip -d /tmp/kubelogin \
    && install -m 0755 /tmp/kubelogin/bin/linux_amd64/kubelogin /usr/local/bin/kubelogin \
    && rm -rf /tmp/kubelogin /tmp/kubelogin.zip

# This tells /bin/sh to source an environment file on startup
ENV ENV=/etc/profile

# Add "start SSH agent if not started" to the startup script
RUN echo '[ ! -f ~/.ssh-agent-env ] && ssh-agent > ~/.ssh-agent-env; source ~/.ssh-agent-env' >> /etc/profile.d/ssh-agent.sh

# Add a flag to the startup script to indicate that the profile has been initialized
RUN echo 'export PROFILE_INITIALIZED=1' >> /etc/profile.d/profile-initialized.sh

# Because we're running as root, we need to set the umask to 0000
# so that any files created by the container are writable outside
# of the container
RUN echo 'umask 0000' > /etc/profile.d/umask.sh

# Make the root directory writable by any user
RUN chmod 777 /root

# Disable Git safe directory checks, so that we can run Git commands in mounted volumes
RUN echo $'\n\
[safe]\n\
    directory = *\n\
' >> /etc/gitconfig

CMD ["sleep", "infinity"]
