#!/bin/bash

# Ubuntu VM Health Check Script
# Monitors CPU, Memory, and Disk usage with detailed explanations
# Usage: ./ubuntu-vm-health.sh [explain]

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Global variables
EXPLAIN_MODE=false
THRESHOLD=60
cpu_healthy=false
memory_healthy=false
disk_healthy=false
cpu_usage=0
memory_usage=0
disk_usage=0

# Check if explain mode is requested
if [ "$1" = "explain" ]; then
    EXPLAIN_MODE=true
fi

echo -e "${BLUE}==============================${NC}"
echo -e "${BLUE}Ubuntu VM Health Check Tool${NC}"
echo -e "${BLUE}==============================${NC}"
echo

# Function to print explanation if in explain mode
print_explanation() {
    local component=$1
    local status=$2
    local usage=$3
    local details=$4
    
    if [ "$EXPLAIN_MODE" = true ]; then
        echo -e "${YELLOW}📝 Explanation for $component:${NC}"
        if [ "$status" = "HEALTHY" ]; then
            echo -e "   ✅ $component is ${GREEN}HEALTHY${NC} because usage (${usage}%) is below the ${THRESHOLD}% threshold"
        else
            echo -e "   ❌ $component is ${RED}UNHEALTHY${NC} because usage (${usage}%) exceeds the ${THRESHOLD}% threshold"
        fi
        if [ -n "$details" ]; then
            echo -e "   ℹ️  Details: $details"
        fi
        echo
    fi
}

# Function to get CPU usage (Ubuntu-specific)
get_cpu_usage() {
    echo "📊 Checking CPU Usage..."
    
    # Method 1: Use vmstat for accurate CPU usage
    if command -v vmstat >/dev/null 2>&1; then
        # Get CPU idle percentage and calculate usage
        cpu_idle=$(vmstat 1 2 | tail -1 | awk '{print $15}')
        cpu_usage=$((100 - cpu_idle))
        
        echo "  Current CPU usage: ${cpu_usage}%"
        echo "  CPU idle: ${cpu_idle}%"
        
        if [ "$cpu_usage" -lt "$THRESHOLD" ]; then
            echo -e "  ✅ CPU status: ${GREEN}HEALTHY${NC} (< ${THRESHOLD}%)"
            cpu_healthy=true
            print_explanation "CPU" "HEALTHY" "$cpu_usage" "System has sufficient CPU resources available"
        else
            echo -e "  ❌ CPU status: ${RED}UNHEALTHY${NC} (≥ ${THRESHOLD}%)"
            print_explanation "CPU" "UNHEALTHY" "$cpu_usage" "High CPU usage may cause performance degradation"
        fi
        
    # Method 2: Use top command as fallback
    elif command -v top >/dev/null 2>&1; then
        cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | sed 's/%us,//' | cut -d'.' -f1)
        
        if [ -n "$cpu_usage" ] && [ "$cpu_usage" -gt 0 ] 2>/dev/null; then
            echo "  Current CPU usage: ${cpu_usage}%"
            
            if [ "$cpu_usage" -lt "$THRESHOLD" ]; then
                echo -e "  ✅ CPU status: ${GREEN}HEALTHY${NC} (< ${THRESHOLD}%)"
                cpu_healthy=true
                print_explanation "CPU" "HEALTHY" "$cpu_usage" "CPU usage obtained from top command"
            else
                echo -e "  ❌ CPU status: ${RED}UNHEALTHY${NC} (≥ ${THRESHOLD}%)"
                print_explanation "CPU" "UNHEALTHY" "$cpu_usage" "High CPU usage detected via top command"
            fi
        else
            # Fallback to load average
            load_avg=$(cat /proc/loadavg 2>/dev/null | awk '{print $1}')
            if [ -n "$load_avg" ]; then
                echo "  Load average (1min): $load_avg"
                # Convert load to approximate percentage (assuming single core)
                cpu_usage=$(awk "BEGIN {printf \"%.0f\", $load_avg * 100}")
                echo "  Approximate CPU usage: ${cpu_usage}%"
                
                if [ "$cpu_usage" -lt "$THRESHOLD" ]; then
                    echo -e "  ✅ CPU status: ${GREEN}HEALTHY${NC} (< ${THRESHOLD}%)"
                    cpu_healthy=true
                    print_explanation "CPU" "HEALTHY" "$cpu_usage" "Based on system load average"
                else
                    echo -e "  ❌ CPU status: ${RED}UNHEALTHY${NC} (≥ ${THRESHOLD}%)"
                    print_explanation "CPU" "UNHEALTHY" "$cpu_usage" "High system load detected"
                fi
            fi
        fi
    else
        echo -e "  ⚠️  ${YELLOW}CPU monitoring tools not available${NC}"
        echo -e "  ℹ️  Assuming CPU is healthy"
        cpu_healthy=true
        cpu_usage=0
        print_explanation "CPU" "HEALTHY" "0" "Monitoring tools unavailable, assuming healthy state"
    fi
}

# Function to get Memory usage (Ubuntu-specific)
get_memory_usage() {
    echo "💾 Checking Memory Usage..."
    
    if [ -f /proc/meminfo ]; then
        # Read memory information from /proc/meminfo
        total_mem=$(grep MemTotal /proc/meminfo | awk '{print $2}')
        available_mem=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
        
        if [ -n "$total_mem" ] && [ -n "$available_mem" ]; then
            used_mem=$((total_mem - available_mem))
            memory_usage=$((used_mem * 100 / total_mem))
            
            echo "  Total Memory: $((total_mem / 1024)) MB"
            echo "  Available Memory: $((available_mem / 1024)) MB"
            echo "  Used Memory: $((used_mem / 1024)) MB"
            echo "  Memory usage: ${memory_usage}%"
            
            if [ "$memory_usage" -lt "$THRESHOLD" ]; then
                echo -e "  ✅ Memory status: ${GREEN}HEALTHY${NC} (< ${THRESHOLD}%)"
                memory_healthy=true
                print_explanation "Memory" "HEALTHY" "$memory_usage" "Sufficient memory available for system operations"
            else
                echo -e "  ❌ Memory status: ${RED}UNHEALTHY${NC} (≥ ${THRESHOLD}%)"
                print_explanation "Memory" "UNHEALTHY" "$memory_usage" "High memory usage may cause swapping and performance issues"
            fi
        else
            echo -e "  ⚠️  ${YELLOW}Cannot read memory statistics${NC}"
            memory_healthy=true
            memory_usage=0
            print_explanation "Memory" "HEALTHY" "0" "Memory statistics unavailable, assuming healthy"
        fi
    else
        echo -e "  ⚠️  ${YELLOW}/proc/meminfo not accessible${NC}"
        memory_healthy=true
        memory_usage=0
        print_explanation "Memory" "HEALTHY" "0" "/proc/meminfo not accessible, assuming healthy"
    fi
}

# Function to get Disk usage (Ubuntu-specific)
get_disk_usage() {
    echo "💿 Checking Disk Usage..."
    
    if command -v df >/dev/null 2>&1; then
        # Get disk usage for root filesystem
        disk_info=$(df -h / 2>/dev/null | tail -1)
        
        if [ -n "$disk_info" ]; then
            disk_usage=$(echo "$disk_info" | awk '{print $5}' | sed 's/%//')
            disk_total=$(echo "$disk_info" | awk '{print $2}')
            disk_used=$(echo "$disk_info" | awk '{print $3}')
            disk_available=$(echo "$disk_info" | awk '{print $4}')
            
            echo "  Total Disk Space: $disk_total"
            echo "  Used Disk Space: $disk_used"
            echo "  Available Disk Space: $disk_available"
            echo "  Disk usage: ${disk_usage}%"
            
            if [ "$disk_usage" -lt "$THRESHOLD" ]; then
                echo -e "  ✅ Disk status: ${GREEN}HEALTHY${NC} (< ${THRESHOLD}%)"
                disk_healthy=true
                print_explanation "Disk" "HEALTHY" "$disk_usage" "Adequate disk space available for system operations"
            else
                echo -e "  ❌ Disk status: ${RED}UNHEALTHY${NC} (≥ ${THRESHOLD}%)"
                print_explanation "Disk" "UNHEALTHY" "$disk_usage" "Low disk space may cause system instability and application failures"
            fi
        else
            echo -e "  ⚠️  ${YELLOW}Cannot determine disk usage${NC}"
            disk_healthy=true
            disk_usage=0
            print_explanation "Disk" "HEALTHY" "0" "Disk usage information unavailable, assuming healthy"
        fi
    else
        echo -e "  ⚠️  ${YELLOW}df command not available${NC}"
        disk_healthy=true
        disk_usage=0
        print_explanation "Disk" "HEALTHY" "0" "df command unavailable, assuming healthy"
    fi
}

# Main execution
echo "Analyzing Ubuntu VM health status..."
echo "Threshold: Resources under ${THRESHOLD}% are considered healthy"
echo

get_cpu_usage
echo
get_memory_usage
echo
get_disk_usage
echo

# Overall Health Assessment
echo -e "${BLUE}==============================${NC}"
echo -e "${BLUE}📋 HEALTH SUMMARY${NC}"
echo -e "${BLUE}==============================${NC}"

# Display individual component status
echo "Component Status:"
[ "$cpu_healthy" = true ] && echo -e "  - CPU: ✅ ${GREEN}Healthy${NC} (${cpu_usage}%)" || echo -e "  - CPU: ❌ ${RED}Unhealthy${NC} (${cpu_usage}%)"
[ "$memory_healthy" = true ] && echo -e "  - Memory: ✅ ${GREEN}Healthy${NC} (${memory_usage}%)" || echo -e "  - Memory: ❌ ${RED}Unhealthy${NC} (${memory_usage}%)"
[ "$disk_healthy" = true ] && echo -e "  - Disk: ✅ ${GREEN}Healthy${NC} (${disk_usage}%)" || echo -e "  - Disk: ❌ ${RED}Unhealthy${NC} (${disk_usage}%)"

echo

# Final health determination
if [ "$cpu_healthy" = true ] && [ "$memory_healthy" = true ] && [ "$disk_healthy" = true ]; then
    echo -e "🟢 ${GREEN}VM STATUS: HEALTHY${NC}"
    
    if [ "$EXPLAIN_MODE" = true ]; then
        echo
        echo -e "${YELLOW}📋 Overall Health Explanation:${NC}"
        echo -e "   ✅ The Ubuntu VM is ${GREEN}HEALTHY${NC} because all monitored resources are below the ${THRESHOLD}% threshold:"
        echo -e "      • CPU usage: ${cpu_usage}% (< ${THRESHOLD}%)"
        echo -e "      • Memory usage: ${memory_usage}% (< ${THRESHOLD}%)"
        echo -e "      • Disk usage: ${disk_usage}% (< ${THRESHOLD}%)"
        echo
        echo -e "   ℹ️  This indicates the system has sufficient resources available and should"
        echo -e "      perform well under normal operating conditions."
    fi
    
    exit 0
else
    echo -e "🔴 ${RED}VM STATUS: UNHEALTHY${NC}"
    
    if [ "$EXPLAIN_MODE" = true ]; then
        echo
        echo -e "${YELLOW}📋 Overall Health Explanation:${NC}"
        echo -e "   ❌ The Ubuntu VM is ${RED}UNHEALTHY${NC} because one or more resources exceed the ${THRESHOLD}% threshold:"
        
        # List problematic resources
        unhealthy_resources=""
        [ "$cpu_healthy" = false ] && unhealthy_resources="${unhealthy_resources}CPU (${cpu_usage}%), "
        [ "$memory_healthy" = false ] && unhealthy_resources="${unhealthy_resources}Memory (${memory_usage}%), "
        [ "$disk_healthy" = false ] && unhealthy_resources="${unhealthy_resources}Disk (${disk_usage}%), "
        
        # Remove trailing comma and space
        unhealthy_resources=$(echo "$unhealthy_resources" | sed 's/, $//')
        
        echo -e "      • Problematic resources: $unhealthy_resources"
        echo
        echo -e "   ⚠️  Recommended actions:"
        [ "$cpu_healthy" = false ] && echo -e "      • CPU: Consider reducing running processes or upgrading CPU resources"
        [ "$memory_healthy" = false ] && echo -e "      • Memory: Close unnecessary applications or add more RAM"
        [ "$disk_healthy" = false ] && echo -e "      • Disk: Clean up files or expand disk storage"
        echo
        echo -e "   ℹ️  High resource utilization may lead to performance degradation and system instability."
    fi
    
    exit 1
fi
