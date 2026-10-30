// MIT License. Supervise only the one runtime child started by this process.
#include <errno.h>
#include <signal.h>
#include <stdlib.h>
#include <sys/types.h>
#include <sys/wait.h>
#include <unistd.h>

static volatile sig_atomic_t stopping = 0;
static void request_stop(int signal_number) { (void)signal_number; stopping = 1; }

static void stop_child(pid_t child) {
    int status;
    if (waitpid(child, &status, WNOHANG) == child) return;
    kill(child, SIGTERM);
    for (int i = 0; i < 30; ++i) {
        if (waitpid(child, &status, WNOHANG) == child) return;
        usleep(100000);
    }
    kill(child, SIGKILL);
    while (waitpid(child, &status, 0) < 0 && errno == EINTR) {}
}

int main(int argc, char **argv) {
    if (argc < 2) return 64;
    pid_t owner = getppid();
    if (owner <= 1) return 1;
    struct sigaction action = {0};
    action.sa_handler = request_stop;
    sigemptyset(&action.sa_mask);
    sigaction(SIGTERM, &action, NULL);
    sigaction(SIGINT, &action, NULL);
    pid_t child = fork();
    if (child < 0) return 1;
    if (child == 0) { execv(argv[1], argv + 1); _exit(127); }
    for (;;) {
        int status;
        pid_t result = waitpid(child, &status, WNOHANG);
        if (result == child) return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
        if (result < 0 && errno != EINTR) return 1;
        if (stopping || getppid() != owner) { stop_child(child); return 0; }
        usleep(250000);
    }
}
