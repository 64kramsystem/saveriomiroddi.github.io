---
layout: post
title: Rust Lulz&#58; Computing matrix cofactors via branchless bit manipulation
tags: [data_types,lulz,performance,rust]
---

This is the beginning of my "Rust Lulz" articles; the subject is simply things that, for one reason or another, I've found amusing while learning/applying Rust.

In this article, I'll explain how to compute the cofactors of a matrix via bit manipulation (assuming an existing `minor()` function).

Content:

- [The boring approach to the problem](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#the-boring-approach-to-the-problem)
- [Walkthrough](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#walkthrough)
  - [Introduce a factor](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#introduce-a-factor)
  - [Sign in number binary representations](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#sign-in-number-binary-representations)
  - [Bit manipulation logic](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#bit-manipulation-logic)
  - [IEEE-754 format](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#ieee-754-format)
    - [Rust bit operations on floats](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#rust-bit-operations-on-floats)
  - [Solution outline](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#solution-outline)
- [Implementation](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#implementation)
- [Conclusion](/Rust-lulz-computing-matrix-cofactors-via-branchless-bit-manipulation#conclusion)

## The boring approach to the problem

Calculating the cofactor of a matrix element (assuming an existing `minor()` function) is a simple problem; we just return the minor, if the element index is positive, and the negated minor otherwise.

In pseudocode:

```
function cofactor(y, x) -> float {
  if (y + x) is even {
    return minor(y, x)
  }
  else {
    return -minor(y, x)
  }
}
```

This is very simple, however, it has two problems: it's _too_ simple, and it has a branch.

Branches are [sworn enemies of processors](https://stackoverflow.com/a/11227902), which are already burdened by [arrested development](https://web.archive.org/web/20201014050811/https://community.cadence.com/cfs-file/__key/communityserver-blogs-components-weblogfiles/00-00-00-01-06/2313.processorperf.jpg), so we ought to help them.

Let's write obscure, potentially slower code but.. code that has The Lulz™!

## Walkthrough

### Introduce a factor

If we make the return values a multiplication between a factor, and the minor, we can rewrite the code to this:

```
function cofactor(y, x) -> float {
  if (y + x) is even {
    return 1 * minor(y, x)
  }
  else {
    return -1 * minor(y, x)
  }
}
```

This will allow us a single code path.

### Sign in number binary representations

The two fundamental number formats in computer technology/science are:

- [Two's complement](https://en.wikipedia.org/wiki/Signed_number_representations#Two's_complement) for signed integers,
- [IEEE-754](https://en.wikipedia.org/wiki/IEEE_754), for floats.

They have something in common: the sign representation. In both cases, a positive number has a sign bit of `0`, while a negative one has a sign bit of `1`.

This leads to an interesting set of possible outcomes (`HL`/`LL` = High/Low Level):

| HL signs | HL result | LL signs | LL result |
| :------: | :-------: | :------: | :-------: |
| `+ • +`  |    `+`    | `0 • 0`  |    `0`    |
| `+ • -`  |    `-`    | `0 • 1`  |    `1`    |
| `- • +`  |    `-`    | `1 • 0`  |    `1`    |
| `- • -`  |    `+`    | `1 • 1`  |    `0`    |

In short, if the signs are equal, they yield a positive (`0`) result; if they're different, they yield a negative (`1`) one.

Reminds something?

Yes! The [`XOR` logical operation](https://en.wikipedia.org/wiki/Exclusive_or)! Between the many usages, it was employed by viruses in the 80s to encrypt their body.

This is the first key to a branchless logic! No, we need to take a step back.

### Bit manipulation logic

Before writing the full logic, we still need a piece (actually, the key!): transforming the parity property of `x + y` into a sign bit, in generic terms:

```
if (y + x) is even {
  return positive sign bit
}
else  {
  return negative sign bit
}
```

A lulzy way of doing this is to sum the two numbers; the least significant bit ("LSB") will be the sign bit!:

|  operation  | operation in bits | Result (LSB) |
| :---------: | :---------------: | :----------: |
| even + even |  xxx`0` + yyy`0`  |   zzzz`0`    |
| even + odd  |  xxx`0` + yyy`1`  |   zzzz`1`    |
| odd + even  |  xxx`1` + yyy`0`  |   zzzz`1`    |
|  odd + odd  |  xxx`1` + yyy`1`  |   zzzz`0`    |

This works because the LSB of an even number is `0`, and the one of an odd number, is `1`.

That's great! We have the base operations in place, now we need some glue.

### IEEE-754 format

Floats are typically internally represented in the [IEEE-754](https://en.wikipedia.org/wiki/IEEE_754) format.

In our case, each minor and the corresponding cofactor are floats; they only differ in the sign. This implies that the underlying bits are the same, except for the sign bit, which, in this format, is the most significant bit ("MSB").

With the knowledge of the floats format specification, we now have all the bits (no pun intended) in place to outline a lulzy solution!

#### Rust bit operations on floats

In Rust we don't have APIs to operate directly on the bits of a float; additionally, Rust has strong rules in place when it comes to low-level manipulation - in other words, we should be in the unsafe realm.

Why "should" and not "are"?

Because due to the ubiquity of the IEEE-754 format, Rust provides APIs to convert a float to a format that we can manipulate, and viceversa.

Enter the scene [`std::f64::to_bits()`](https://doc.rust-lang.org/std/primitive.f64.html#method.to_bits) and [`std::f64::from_bits()`](https://doc.rust-lang.org/std/primitive.f64.html#method.from_bits): with these APIs, we can convert to u64, perform the bit operations, then convert back to f64.

### Solution outline

The general solution logic is:

- sum `x` and `y`, and isolate the LSB;
- in the resulting variable, shift the bit, putting it in the location corresponding to the sign bit of an IEEE-754 encoded float
- xor the minor and the the resulting value.

Let's implement the steps.

Convert the minor to bits, in order to manipulate them:

```rust
let minor_bits = minor.to_bits();
```

sum them:

```rust
let minor_bits_sum = x + y;
```

isolate and move to the expected place, in one swoop!:

```rust
let sign_bit = minor_bits_sum << 63;
```

the above is interesting, because we're essentially applying a bitmask: all the bits on the left of the LSB will be thrown away, due to how shifting works.

apply the xor operation to the minor sign bit:

```rust
let result_bits = minor_bits ^ sign_bit;
```

and finally, convert to f64:

```rust
f64::from_bits(result_bits)
```

## Implementation

This is the implementation, shortened a bit, and with comments:

```rust
pub fn cofactor(&self, y: usize, x: usize) -> f64 {
    let minor = self.minor(y, x);

    // The data type is irrelevant here, as long as it supports bit shifts (float doesn't).
    // usize is used for convenience on the next operation.
    //
    let minor_bits = minor.to_bits();

    // This is (0 for even/1 for odd), shifted to be the leftmost bit, so that it's in the sign position
    // of f64 values.
    //
    let sign_bits = ((x + y) << 63) as u64;

    // Xor keeps the <destination sign> if the <sign operand> is 0, and changes it, if the <sign operand> is 1.
    //
    f64::from_bits(minor_bits ^ sign_bits)
}
```

It uses `usize` as input, because when accessing a matrix, likely, `x` and `y` will be indexes of an array/vector.

## Conclusion

We've produced obscure and potentially slower code... but code that is approved by Real Programmers™, especially because it's been implemented in Rust.

I appreciate the fact that there are official APIs to perform low-level manipulation of `f64` numbers; considering that in Rust, such operations are typically unsafe, this is, in my opinion, a sign of how Rust has a rigorous approach, while at the same time, being pragmatic.

Happy Rust programming!
