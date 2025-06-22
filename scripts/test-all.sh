#!/bin/bash

# Comprehensive test script for MCP Dart library
# Runs both VM and web tests with proper error handling

set -e  # Exit on any error

echo "🧪 MCP Dart Comprehensive Test Suite"
echo "===================================="
echo ""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}$1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Check if required tools are installed
check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v dart &> /dev/null; then
        print_error "Dart SDK not found. Please install Dart."
        exit 1
    fi
    
    if ! command -v chrome &> /dev/null && ! command -v google-chrome &> /dev/null; then
        print_warning "Chrome not found. Web tests may fail."
    fi
    
    print_success "Dependencies check passed"
}

# Run VM tests
run_vm_tests() {
    print_status "Running VM tests..."
    
    if dart test --exclude-tags=web-only; then
        print_success "VM tests passed"
        return 0
    else
        print_error "VM tests failed"
        return 1
    fi
}

# Run web tests
run_web_tests() {
    print_status "Running web tests in Chrome..."
    
    if dart test test/web/ -p chrome; then
        print_success "Web tests passed"
        return 0
    else
        print_error "Web tests failed"
        return 1
    fi
}

# Test web compilation
test_compilation() {
    print_status "Testing web compilation..."
    
    if dart compile js example/web_example.dart -o example/web_example.js; then
        print_success "Web compilation successful"
        # Clean up generated file
        rm -f example/web_example.js example/web_example.js.map
        return 0
    else
        print_error "Web compilation failed"
        return 1
    fi
}

# Main execution
main() {
    local start_time=$(date +%s)
    local failed_tests=()
    
    check_dependencies
    echo ""
    
    # Run VM tests
    if ! run_vm_tests; then
        failed_tests+=("VM tests")
    fi
    echo ""
    
    # Run web tests
    if ! run_web_tests; then
        failed_tests+=("Web tests")
    fi
    echo ""
    
    # Test compilation
    if ! test_compilation; then
        failed_tests+=("Web compilation")
    fi
    echo ""
    
    # Summary
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))
    
    echo "=================================="
    if [ ${#failed_tests[@]} -eq 0 ]; then
        print_success "All tests passed! 🎉"
        print_success "Total time: ${duration}s"
        exit 0
    else
        print_error "Some tests failed:"
        for test in "${failed_tests[@]}"; do
            print_error "  - $test"
        done
        exit 1
    fi
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --vm-only)
            VM_ONLY=true
            shift
            ;;
        --web-only)
            WEB_ONLY=true
            shift
            ;;
        --no-compile)
            NO_COMPILE=true
            shift
            ;;
        -h|--help)
            echo "Usage: $0 [OPTIONS]"
            echo ""
            echo "Options:"
            echo "  --vm-only     Run only VM tests"
            echo "  --web-only    Run only web tests"
            echo "  --no-compile  Skip compilation test"
            echo "  -h, --help    Show this help"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Conditional execution based on flags
if [[ "$VM_ONLY" == true ]]; then
    check_dependencies
    run_vm_tests
elif [[ "$WEB_ONLY" == true ]]; then
    check_dependencies
    run_web_tests
    if [[ "$NO_COMPILE" != true ]]; then
        test_compilation
    fi
else
    main
fi
