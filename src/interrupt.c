// Signal handling for Jarvis
#include <signal.h>
#include <stdbool.h>
#include <stddef.h>

static volatile sig_atomic_t interrupt_requested = 0;

// Signal handler for SIGINT (Ctrl+C)
static void sigint_handler(int sig) {
    (void)sig;
    interrupt_requested = 1;
}

// Initialize signal handling
void jarvis_signal_init(void) {
    struct sigaction sa;
    sa.sa_handler = sigint_handler;
    sigemptyset(&sa.sa_mask);
    sa.sa_flags = 0;
    sigaction(SIGINT, &sa, NULL);
}

// Check if interrupt was requested
bool jarvis_signal_check_interrupt(void) {
    return interrupt_requested != 0;
}

// Clear interrupt flag
void jarvis_signal_clear_interrupt(void) {
    interrupt_requested = 0;
}

// Get SIGINT constant
int jarvis_signal_sigint(void) {
#ifdef SIGINT
    return SIGINT;
#else
    return -1;
#endif
}
