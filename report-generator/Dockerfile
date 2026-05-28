FROM ubuntu:22.04

ENV DEBIAN_FRONTEND=noninteractive

# Add TinyTeX to PATH for all subsequent RUN steps and at runtime
ENV PATH="/root/.TinyTeX/bin/x86_64-linux:${PATH}"

# 1. Install system utilities, Python 3, and Perl (required by tlmgr)
RUN apt-get update && apt-get install -y --no-install-recommends \
    wget \
    curl \
    ca-certificates \
    xz-utils \
    pandoc \
    lmodern \
    python3 \
    python3-pip \
    perl \
    libfile-find-rule-perl \
    && rm -rf /var/lib/apt/lists/*

# 2. Download and install Quarto CLI (v1.9.38)
RUN wget https://github.com/quarto-dev/quarto-cli/releases/download/v1.9.38/quarto-1.9.38-linux-amd64.deb \
    && apt-get install -y ./quarto-1.9.38-linux-amd64.deb \
    && rm ./quarto-1.9.38-linux-amd64.deb \
    && rm -rf /var/lib/apt/lists/*

# 3. Install TinyTeX via Quarto
RUN quarto install tinytex --no-prompt

# 4. Pre-install known required LaTeX packages
RUN tlmgr install luatexbase luaotfload

# 5. Pre-generate the luaotfload font name database
RUN luaotfload-tool --update --force

# 6. Install Python dependencies
COPY requirements.txt /tmp/requirements.txt
RUN pip3 install --no-cache-dir -r /tmp/requirements.txt \
    && rm /tmp/requirements.txt

# 7. Set working directory and copy app
WORKDIR /app
COPY . /app

# 8. Give execution permissions to the script
RUN chmod +x /app/generate_reports.sh

# 9. Set the entry point for the report generator
ENTRYPOINT ["/bin/bash", "/app/generate_reports.sh"]

