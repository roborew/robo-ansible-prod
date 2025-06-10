#!/usr/bin/env python3
"""
Containerized Ansible Control Node Webhook Service
Handles GitHub/GitLab webhooks and executes Ansible deployments
"""

import os
import sys
import json
import time
import hmac
import hashlib
import subprocess
import threading
import logging
from datetime import datetime
from pathlib import Path
import yaml
import requests
from flask import Flask, request, jsonify

# Configuration from environment
WEBHOOK_PORT = int(os.environ.get("WEBHOOK_PORT", 9000))
WEBHOOK_SECRET = os.environ.get("WEBHOOK_SECRET", "change-me-secure-secret")
LOG_LEVEL = os.environ.get("LOG_LEVEL", "INFO")
ANSIBLE_PROJECT_DIR = "/ansible"
ANSIBLE_INVENTORY = "/ansible/inventory/hosts.yml"
ANSIBLE_CONFIG = "/ansible/ansible.cfg"

# Setup logging
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL),
    format="%(asctime)s - %(name)s - %(levelname)s - %(message)s",
    handlers=[
        logging.FileHandler("/ansible/logs/webhook.log"),
        logging.StreamHandler(sys.stdout),
    ],
)
logger = logging.getLogger(__name__)

# Flask app
app = Flask(__name__)
app.logger.setLevel(getattr(logging, LOG_LEVEL))

# Global state
active_deployments = {}
deployment_lock = threading.Lock()
shutdown_flag = threading.Event()


def load_config():
    """Load deployment configuration"""
    try:
        config_path = Path("/ansible/group_vars/prod.yml")
        if config_path.exists():
            with open(config_path, "r") as f:
                return yaml.safe_load(f)
        else:
            logger.error(f"Configuration file not found: {config_path}")
            return None
    except Exception as e:
        logger.error(f"Failed to load configuration: {e}")
        return None


def verify_signature(payload, signature):
    """Verify GitHub/GitLab webhook signature"""
    if not signature:
        return False

    try:
        # GitHub format: sha256=<hash>
        if signature.startswith("sha256="):
            expected = hmac.new(
                WEBHOOK_SECRET.encode(), payload, hashlib.sha256
            ).hexdigest()
            return hmac.compare_digest(f"sha256={expected}", signature)

        # GitLab format: just the token
        return hmac.compare_digest(WEBHOOK_SECRET, signature)

    except Exception as e:
        logger.error(f"Signature verification error: {e}")
        return False


def extract_push_info(payload):
    """Extract push information from webhook payload"""
    try:
        if "repository" in payload and "commits" in payload:
            # GitHub format
            repo_url = payload["repository"]["clone_url"]
            repo_name = payload["repository"]["name"]
            branch = payload["ref"].replace("refs/heads/", "")

            if payload["commits"]:
                latest_commit = payload["commits"][-1]
                commit_sha = latest_commit["id"]
                commit_message = latest_commit["message"]
                pusher = latest_commit["author"]["name"]
            else:
                commit_sha = payload.get("after", "unknown")
                commit_message = "No commit message"
                pusher = payload.get("pusher", {}).get("name", "unknown")

            return {
                "repo_url": repo_url,
                "repo_name": repo_name,
                "branch": branch,
                "commit_sha": commit_sha,
                "commit_message": commit_message,
                "pusher": pusher,
                "provider": "github",
            }

        elif "project" in payload:
            # GitLab format
            repo_url = payload["project"]["http_url"]
            repo_name = payload["project"]["name"]
            branch = payload["ref"].replace("refs/heads/", "")

            if payload.get("commits"):
                latest_commit = payload["commits"][-1]
                commit_sha = latest_commit["id"]
                commit_message = latest_commit["message"]
                pusher = latest_commit["author"]["name"]
            else:
                commit_sha = payload.get("after", "unknown")
                commit_message = "No commit message"
                pusher = payload.get("user_name", "unknown")

            return {
                "repo_url": repo_url,
                "repo_name": repo_name,
                "branch": branch,
                "commit_sha": commit_sha,
                "commit_message": commit_message,
                "pusher": pusher,
                "provider": "gitlab",
            }

    except Exception as e:
        logger.error(f"Failed to extract push info: {e}")
        return None


def find_matching_app(config, push_info):
    """Find app configuration that matches the push"""
    if not config or "apps" not in config:
        return None

    for app in config["apps"]:
        if not app.get("auto_deploy", {}).get("enabled", False):
            continue

        # Check if repository matches
        app_repo = app["repo"].lower()
        push_repo = push_info["repo_url"].lower()

        # Handle different URL formats
        if app_repo.endswith(".git"):
            app_repo = app_repo[:-4]
        if push_repo.endswith(".git"):
            push_repo = push_repo[:-4]

        # Normalize URLs for comparison
        app_repo_normalized = (
            app_repo.replace("https://", "")
            .replace("git@", "")
            .replace("github.com:", "github.com/")
        )
        push_repo_normalized = (
            push_repo.replace("https://", "")
            .replace("git@", "")
            .replace("github.com:", "github.com/")
        )

        if app_repo_normalized != push_repo_normalized:
            continue

        # Check if branch is configured for auto-deploy
        auto_deploy_config = app.get("auto_deploy", {})
        for branch_config in auto_deploy_config.get("branches", []):
            if branch_config["name"] == push_info["branch"]:
                return {
                    "app": app,
                    "branch_config": branch_config,
                    "push_info": push_info,
                }

    return None


def deploy_app(app_name, branch, environment, push_info):
    """Execute deployment using Ansible"""
    deployment_id = f"{app_name}-{branch}-{int(time.time())}"

    try:
        with deployment_lock:
            active_deployments[deployment_id] = {
                "app": app_name,
                "branch": branch,
                "environment": environment,
                "started": datetime.now().isoformat(),
                "status": "running",
                "push_info": push_info,
            }

        logger.info(f"Starting deployment: {deployment_id}")
        logger.info(f"Deploying {app_name} branch '{branch}' to {environment}")
        logger.info(f"Commit: {push_info['commit_sha'][:8]} by {push_info['pusher']}")

        # Create deployment log file
        deploy_log = f"/ansible/logs/deploy_{deployment_id}.log"

        # Prepare Ansible command
        ansible_cmd = [
            "ansible-playbook",
            "/ansible/playbooks/deploy.yml",
            "-i",
            ANSIBLE_INVENTORY,
            "-e",
            f"mode=branch",
            "-e",
            f"branch={branch}",
            "-e",
            f"app={app_name}",
            "-e",
            f"deploy_environment={environment}",
            "-e",
            f"auto_deploy=true",
            "-e",
            f"deployment_id={deployment_id}",
        ]

        # Set environment
        env = os.environ.copy()
        env["ANSIBLE_CONFIG"] = ANSIBLE_CONFIG
        env["ANSIBLE_HOST_KEY_CHECKING"] = "False"

        logger.info(f"Running: {' '.join(ansible_cmd)}")

        # Execute Ansible deployment
        with open(deploy_log, "w") as log_file:
            result = subprocess.run(
                ansible_cmd,
                cwd=ANSIBLE_PROJECT_DIR,
                stdout=log_file,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=1800,  # 30 minutes timeout
                env=env,
            )

        # Read deployment output
        with open(deploy_log, "r") as log_file:
            deploy_output = log_file.read()

        # Update deployment status
        with deployment_lock:
            if deployment_id in active_deployments:
                active_deployments[deployment_id].update(
                    {
                        "status": "success" if result.returncode == 0 else "failed",
                        "completed": datetime.now().isoformat(),
                        "exit_code": result.returncode,
                        "log_file": deploy_log,
                        "output": deploy_output[-1000:] if deploy_output else "",
                    }
                )

        if result.returncode == 0:
            logger.info(f"Deployment successful: {deployment_id}")
        else:
            logger.error(f"Deployment failed: {deployment_id}")

    except Exception as e:
        logger.error(f"Deployment error: {deployment_id} - {e}")
        with deployment_lock:
            if deployment_id in active_deployments:
                active_deployments[deployment_id].update(
                    {
                        "status": "error",
                        "completed": datetime.now().isoformat(),
                        "error": str(e),
                    }
                )


def schedule_deployment(match_data):
    """Schedule deployment with delay"""

    def delayed_deploy():
        time.sleep(30)  # Deploy delay

        app_name = match_data["app"]["name"]
        branch = match_data["branch_config"]["name"]
        environment = match_data["branch_config"]["environment"]
        push_info = match_data["push_info"]

        deploy_app(app_name, branch, environment, push_info)

    thread = threading.Thread(target=delayed_deploy)
    thread.daemon = True
    thread.start()


@app.route("/health")
def health():
    """Health check endpoint"""
    return jsonify(
        {
            "status": "healthy",
            "timestamp": datetime.now().isoformat(),
            "active_deployments": len(
                [d for d in active_deployments.values() if d["status"] == "running"]
            ),
            "control_node": "containerized",
            "ansible_project": ANSIBLE_PROJECT_DIR,
        }
    )


@app.route("/deployments")
def list_deployments():
    """List active deployments"""
    return jsonify(
        {
            "deployments": list(active_deployments.values()),
            "total": len(active_deployments),
        }
    )


@app.route("/webhook", methods=["POST"])
def webhook():
    """Main webhook endpoint"""
    try:
        # Verify signature
        signature = request.headers.get("X-Hub-Signature-256") or request.headers.get(
            "X-GitLab-Token"
        )
        if not verify_signature(request.data, signature):
            logger.warning(f"Invalid webhook signature from {request.remote_addr}")
            return jsonify({"error": "Invalid signature"}), 401

        # Parse payload
        payload = request.get_json()
        if not payload:
            return jsonify({"error": "Invalid JSON payload"}), 400

        # Extract push information
        push_info = extract_push_info(payload)
        if not push_info:
            return jsonify({"error": "Unable to extract push information"}), 400

        logger.info(
            f"Received push for {push_info['repo_name']}:{push_info['branch']} from {push_info['pusher']}"
        )

        # Load current configuration
        config = load_config()
        if not config:
            return jsonify({"error": "Configuration not available"}), 500

        # Find matching app configuration
        match_data = find_matching_app(config, push_info)
        if not match_data:
            logger.info(
                f"No auto-deploy configuration found for {push_info['repo_name']}:{push_info['branch']}"
            )
            return jsonify({"message": "No matching auto-deploy configuration"}), 200

        # Schedule deployment
        schedule_deployment(match_data)

        return (
            jsonify(
                {
                    "message": "Deployment scheduled",
                    "app": match_data["app"]["name"],
                    "branch": push_info["branch"],
                    "environment": match_data["branch_config"]["environment"],
                    "delay": 30,
                }
            ),
            200,
        )

    except Exception as e:
        logger.error(f"Webhook error: {e}")
        return jsonify({"error": "Internal server error"}), 500


if __name__ == "__main__":
    logger.info("Starting Ansible Control Node Webhook Service")
    logger.info(f"Webhook port: {WEBHOOK_PORT}")
    logger.info(f"Ansible project: {ANSIBLE_PROJECT_DIR}")

    # Ensure log directory exists
    os.makedirs("/ansible/logs", exist_ok=True)

    # Start Flask app
    app.run(host="0.0.0.0", port=WEBHOOK_PORT, debug=False)
