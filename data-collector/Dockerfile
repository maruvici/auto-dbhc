FROM ubuntu:22.04

# Install SSH, Sudo, and basic tools
RUN apt-get update && apt-get install -y openssh-server sudo iputils-ping

# Create the Oracle User
RUN useradd -m -s /bin/bash oracle && \
    echo 'oracle:oracle' | chpasswd && \
    echo 'root:password123' | chpasswd

# Enable SSH Root Login (for testing only)
RUN sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin yes/' /etc/ssh/sshd_config

# Copy the setup script into the image
COPY mock_setup.sh /usr/local/bin/mock_setup.sh
RUN chmod +x /usr/local/bin/mock_setup.sh

# Run the setup script on container start
CMD ["/usr/local/bin/mock_setup.sh"]