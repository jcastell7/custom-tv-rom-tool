// Stock's wpa_supplicant and hostapd were built against a BoringSSL that exported sk_dup. Ours exports it as OPENSSL_sk_dup.
#include <openssl/stack.h>

OPENSSL_EXPORT OPENSSL_STACK *sk_dup(const OPENSSL_STACK *sk);

OPENSSL_STACK *sk_dup(const OPENSSL_STACK *sk) {
    return OPENSSL_sk_dup(sk);
}
