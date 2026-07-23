// bench_binary_tree.c - BST insert + inorder sum benchmark
#include "bench_timer.h"

typedef struct BNode {
    int value;
    struct BNode *left;
    struct BNode *right;
} BNode;

static BNode *bst_insert(BNode *root, int val) {
    if (root == NULL) {
        BNode *n = (BNode *)malloc(sizeof(BNode));
        n->value = val;
        n->left = NULL;
        n->right = NULL;
        return n;
    }
    if (val < root->value) {
        root->left = bst_insert(root->left, val);
    } else {
        root->right = bst_insert(root->right, val);
    }
    return root;
}

static long long bst_sum(BNode *root) {
    if (root == NULL) return 0;
    return bst_sum(root->left) + root->value + bst_sum(root->right);
}

static void bst_free(BNode *root) {
    if (root == NULL) return;
    bst_free(root->left);
    bst_free(root->right);
    free(root);
}

static long long run_tree(int n) {
    long long state = 31337;
    BNode *root = NULL;
    for (int i = 0; i < n; i++) {
        state = state * 6364136223846793005LL + 1442695040888963407LL;
        int val = (int)((state >> 33) & 2147483647LL);
        root = bst_insert(root, val);
    }
    long long result = bst_sum(root);
    bst_free(root);
    return result;
}

int main(void) {
    int n = 500000;

    // Warm up
    long long result = run_tree(n);

    bench_time_t t1, t2;
    bench_timer_start(&t1);
    for (int iter = 0; iter < 8; iter++) {
        result = run_tree(n);
        BENCH_USE(result);
    }
    bench_timer_start(&t2);

    long long elapsed = bench_elapsed_us(t1, t2);
    printf("binary_tree: result=%lld time=%lld us\n", result, elapsed);
    return 0;
}
