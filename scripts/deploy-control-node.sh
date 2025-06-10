#!/bin/bash

# Deploy Containerized Ansible Control Node to DigitalOcean
# Usage: ./scripts/deploy-control-node.sh [server-ip] [action]

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
CONTROL_SERVER="$1"
ACTION="${2:-deploy}"
CONTROL_DIR="/opt/ansible-control"
DOCKER_COMPOSE_PROJECT="ansible-control"

if [ -z "$CONTROL_SERVER" ]; then
    echo -e "${RED}Usage: $0 <server-ip> [action]${NC}"
    echo "Actions: deploy, start, stop, restart, logs, status, update"
    exit 1
fi

show_help() {
    echo -e "${BLUE}🎛️ Containerized Ansible Control Node Deployment${NC}"
    echo "=================================================="
    echo ""
    echo "Usage: $0 <server-ip> [action]"
    echo ""
    echo "Actions:"
    echo "  deploy     Deploy control node to server (default)"
    echo "  start      Start the control node service"
    echo "  stop       Stop the control node service"
    echo "  restart    Restart the control node service"
    echo "  logs       View control node logs"
    echo "  status     Check control node status"
    echo "  update     Update control node (pull latest config)"
    echo "  shell      SSH into control node container"
    echo "  webhook    Show webhook configuration"
    echo ""
    echo "Examples:"
    echo "  $0 192.168.1.100 deploy"
    echo "  $0 192.168.1.100 logs"
    echo "  $0 192.168.1.100 status"
}

check_ssh_connection() {
    echo -e "${BLUE}🔍 Checking SSH connection to $CONTROL_SERVER...${NC}"
    if ! ssh -o ConnectTimeout=5 -o BatchMode=yes root@$CONTROL_SERVER exit 2>/dev/null; then
        echo -e "${RED}❌ Cannot connect to $CONTROL_SERVER${NC}"
        echo "Please ensure:"
        echo "1. Server is running and accessible"
        echo "2. SSH key is properly configured"
        echo "3. User has sudo privileges"
        exit 1
    fi
    echo -e "${GREEN}✅ SSH connection successful${NC}"
}

deploy_control_node() {
    echo -e "${BLUE}🚀 Deploying Ansible Control Node to $CONTROL_SERVER${NC}"
    
    # Create control directory on server
    ssh root@$CONTROL_SERVER "mkdir -p $CONTROL_DIR"
    
    # Copy Docker files
    echo -e "${YELLOW}📦 Copying Docker configuration...${NC}"
    scp -r docker/control-node/* root@$CONTROL_SERVER:$CONTROL_DIR/
    
    # Copy Ansible project files
    echo -e "${YELLOW}📁 Copying Ansible project...${NC}"
    ssh root@$CONTROL_SERVER "mkdir -p $CONTROL_DIR/{config,inventory,group_vars,playbooks,roles}"
    
    scp ansible.cfg root@$CONTROL_SERVER:$CONTROL_DIR/config/ 2>/dev/null || true
    scp -r inventory/* root@$CONTROL_SERVER:$CONTROL_DIR/inventory/ 2>/dev/null || true
    scp -r group_vars/* root@$CONTROL_SERVER:$CONTROL_DIR/group_vars/ 2>/dev/null || true
    scp -r playbooks/* root@$CONTROL_SERVER:$CONTROL_DIR/playbooks/ 2>/dev/null || true
    scp -r roles/* root@$CONTROL_SERVER:$CONTROL_DIR/roles/ 2>/dev/null || true
    
    # Copy SSH keys (if they exist)
    echo -e "${YELLOW}🔑 Copying SSH keys...${NC}"
    if [ -f ~/.ssh/id_rsa ]; then
        ssh root@$CONTROL_SERVER "mkdir -p $CONTROL_DIR/ssh-keys"
        scp ~/.ssh/id_rsa* root@$CONTROL_SERVER:$CONTROL_DIR/ssh-keys/ 2>/dev/null || true
    fi
    
    # Create environment file
    echo -e "${YELLOW}⚙️ Setting up environment...${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && cp env.example .env"
    
    # Build and start
    echo -e "${YELLOW}🏗️ Building and starting control node...${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose build && docker-compose up -d"
    
    # Wait for service to start
    echo -e "${YELLOW}⏳ Waiting for service to start...${NC}"
    sleep 10
    
    # Check status
    check_status
    
    echo -e "${GREEN}🎉 Control node deployed successfully!${NC}"
    show_webhook_info
}

start_service() {
    echo -e "${BLUE}🚀 Starting control node service...${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose up -d"
    sleep 5
    check_status
}

stop_service() {
    echo -e "${BLUE}🛑 Stopping control node service...${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose down"
}

restart_service() {
    echo -e "${BLUE}🔄 Restarting control node service...${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose restart"
    sleep 5
    check_status
}

show_logs() {
    echo -e "${BLUE}📋 Control node logs:${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose logs -f --tail=50"
}

check_status() {
    echo -e "${BLUE}📊 Control node status:${NC}"
    
    # Check container status
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose ps"
    
    # Check health endpoint
    echo -e "\n${YELLOW}🏥 Health check:${NC}"
    if ssh root@$CONTROL_SERVER "curl -s http://localhost:9000/health" 2>/dev/null; then
        echo -e "\n${GREEN}✅ Control node is healthy${NC}"
    else
        echo -e "\n${RED}❌ Control node health check failed${NC}"
    fi
    
    # Check deployments
    echo -e "\n${YELLOW}🚀 Active deployments:${NC}"
    ssh root@$CONTROL_SERVER "curl -s http://localhost:9000/deployments" 2>/dev/null || echo "No deployment info available"
}

update_control_node() {
    echo -e "${BLUE}🔄 Updating control node configuration...${NC}"
    
    # Copy updated files
    scp -r inventory/* root@$CONTROL_SERVER:$CONTROL_DIR/inventory/ 2>/dev/null || true
    scp -r group_vars/* root@$CONTROL_SERVER:$CONTROL_DIR/group_vars/ 2>/dev/null || true
    scp -r playbooks/* root@$CONTROL_SERVER:$CONTROL_DIR/playbooks/ 2>/dev/null || true
    scp -r roles/* root@$CONTROL_SERVER:$CONTROL_DIR/roles/ 2>/dev/null || true
    
    # Restart to pick up changes
    restart_service
    
    echo -e "${GREEN}✅ Control node updated${NC}"
}

shell_access() {
    echo -e "${BLUE}🐚 Accessing control node shell...${NC}"
    ssh root@$CONTROL_SERVER "cd $CONTROL_DIR && docker-compose exec ansible-control bash"
}

show_webhook_info() {
    echo -e "\n${BLUE}📡 Webhook Configuration${NC}"
    echo "========================"
    echo -e "${YELLOW}Webhook URL:${NC} http://$CONTROL_SERVER:9000/webhook"
    echo -e "${YELLOW}Health Check:${NC} http://$CONTROL_SERVER:9000/health"
    echo -e "${YELLOW}Deployments:${NC} http://$CONTROL_SERVER:9000/deployments"
    echo ""
    echo -e "${YELLOW}📋 GitHub Webhook Setup:${NC}"
    echo "1. Go to Repository → Settings → Webhooks"
    echo "2. Add webhook with URL: http://$CONTROL_SERVER:9000/webhook"
    echo "3. Set Content-Type: application/json"
    echo "4. Set Secret: (from your .env file)"
    echo "5. Select 'Just the push event'"
    echo ""
    echo -e "${YELLOW}🔧 Management Commands:${NC}"
    echo "# View logs:     $0 $CONTROL_SERVER logs"
    echo "# Check status:  $0 $CONTROL_SERVER status"
    echo "# Update config: $0 $CONTROL_SERVER update"
    echo "# Shell access:  $0 $CONTROL_SERVER shell"
}

# Main execution
case "$ACTION" in
    "help"|"-h"|"--help")
        show_help
        ;;
    "deploy")
        check_ssh_connection
        deploy_control_node
        ;;
    "start")
        check_ssh_connection
        start_service
        ;;
    "stop")
        check_ssh_connection
        stop_service
        ;;
    "restart")
        check_ssh_connection
        restart_service
        ;;
    "logs")
        check_ssh_connection
        show_logs
        ;;
    "status")
        check_ssh_connection
        check_status
        ;;
    "update")
        check_ssh_connection
        update_control_node
        ;;
    "shell")
        check_ssh_connection
        shell_access
        ;;
    "webhook")
        show_webhook_info
        ;;
    *)
        echo -e "${RED}Unknown action: $ACTION${NC}"
        show_help
        exit 1
        ;;
esac 