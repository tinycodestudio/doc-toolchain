/**
 * @file greet.h
 * @brief Tiny example API used to demonstrate the doc-toolchain.
 *
 * This header exists purely so `doc-toolchain` has something to document in its
 * standalone example. It shows the Doxygen comment style the toolchain expects.
 */
#ifndef GREET_H
#define GREET_H

/** @brief Language a greeting can be rendered in. */
typedef enum {
    GREET_EN, /**< English  */
    GREET_FR, /**< French   */
    GREET_DE  /**< German   */
} greet_lang_t;

/**
 * @brief Write a greeting for @p name into @p buf.
 *
 * @param buf   Destination buffer (must be non-NULL).
 * @param cap   Capacity of @p buf in bytes, including the NUL terminator.
 * @param name  Name to greet; if NULL, a generic greeting is used.
 * @param lang  Language to greet in.
 * @return Number of bytes written (excluding the NUL), or -1 on error.
 */
int greet_format(char *buf, unsigned cap, const char *name, greet_lang_t lang);

#endif /* GREET_H */
