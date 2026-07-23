// bench_list_sum.c - linked list traversal benchmark
#include "bench_timer.h"

typedef struct ListNode {
    int value;
    struct ListNode *next;
} ListNode;

static ListNode *build_list(int n) {
    ListNode *nodes = (ListNode *)malloc((size_t)n * sizeof(ListNode));
    // Initialize values
    long long state = 88888;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        nodes[i].value = (int)((state >> 33) & 0xFFFF);
        nodes[i].next = NULL;
    }
    // Fisher-Yates shuffle to randomize traversal order
    int *order = (int *)malloc((size_t)n * sizeof(int));
    for (int i = 0; i < n; i++) order[i] = i;
    state = 99999;
    for (int i = n - 1; i > 0; i--) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        int j = (int)((unsigned long long)(state >> 33) % (unsigned long long)(i + 1));
        int tmp = order[i]; order[i] = order[j]; order[j] = tmp;
    }
    // Link nodes in shuffled order
    for (int i = 0; i < n - 1; i++) {
        nodes[order[i]].next = &nodes[order[i + 1]];
    }
    ListNode *head = &nodes[order[0]];
    free(order);
    return head;
}

static long long list_sum(ListNode *head) {
    long long sum = 0;
    ListNode *cur = head;
    while (cur != NULL) {
        sum += (long long)cur->value;
        cur = cur->next;
    }
    return sum;
}

int main(void) {
    int n = 1000000;
    ListNode *head = build_list(n);

    // Warm up
    long long result = list_sum(head);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 200; iter++) {
        result = list_sum(head);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("list_sum: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
