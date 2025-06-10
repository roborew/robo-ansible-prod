FROM python:3.11-slim

# Install system dependencies
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    curl \
    rsync \
    && rm -rf /var/lib/apt/lists/*

# Create ansible user
RUN useradd -m -s /bin/bash ansible

# Set working directory
WORKDIR /ansible

# Install Python dependencies
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy SSH configuration
RUN mkdir -p /home/ansible/.ssh && \
    chown -R ansible:ansible /home/ansible/.ssh && \
    chmod 700 /home/ansible/.ssh

# Copy Ansible project
COPY --chown=ansible:ansible . .

# Create necessary directories
RUN mkdir -p /ansible/logs /ansible/ssh-keys && \
    chown -R ansible:ansible /ansible

# Switch to ansible user
USER ansible

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:9000/health || exit 1

# Expose webhook port
EXPOSE 9000

# Default command
CMD ["python", "/ansible/webhook_service.py"] 