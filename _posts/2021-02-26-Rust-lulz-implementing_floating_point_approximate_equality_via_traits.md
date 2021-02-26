---
layout: post
title: Rust Lulz&#58; Implementing (floating point) approximate equality via traits
tags: [data_types,lulz,rust]
---

A common concept to deal with when working with floating point numbers, is approximate equality. While the implementation itself is simple (a specialized function will do), Rust gives a more elegant option.

In this article, I'll explain how to implement approximate equality via traits.

Content:

- [The basic approach to the problem](/Rust-lulz-implementing_floating_point_approximate_equality_via_traits#the-basic-approach-to-the-problem)
- [The doubt](/Rust-lulz-implementing_floating_point_approximate_equality_via_traits#the-doubt)
- [The solution](/Rust-lulz-implementing_floating_point_approximate_equality_via_traits#the-solution)
- [Implementing the solution on a trait](/Rust-lulz-implementing_floating_point_approximate_equality_via_traits#implementing-the-solution-on-a-trait)
- [Conclusion](/Rust-lulz-implementing_floating_point_approximate_equality_via_traits#conclusion)

## The basic approach to the problem

The logic to perform approximate equality between floating point numbers is trivial:

```
abs(n1 - n2) < ε
```

In Rust, we can simply define a constant, and a function that takes two floats:

```rust
const EPSILON: f64 = 0.00001;

fn approximate_eq(n1: f64, n2: f64) -> bool {
  (n1 - n2).abs() < EPSILON
}
```

## The doubt

The design above raises a strong doubt: where should the logic be placed?

It doesn't belong to a very specific place in the program. It would be convenient to associate it to f64, but it is a built-in data type; in general, it may be a type defined in an external crate.

Rust, however, allows adding behavior to any type (putting in place appropriate constraints), which is perfect for the case.

## The solution

The solution, implemented via traits, is actually very simple.

We define a trait that defines the epsilon constant and the method that tests for approximate equality:

```rust
trait ApproximateEq {
    const EPSILON: f64 = 0.00001;

    fn approximate_eq(self, other: Self) -> bool;
}
```

This looks better: the epsilon constant and the function are not hanging around anymore.

There are a couple of details worth reviewing:

1. the function is going to own the object, as it uses `self` (as opposed to the reference `&self`); in this context, this doesn't matter, as `f64` is `Copy`
2. `Self` is used as type of the right operand; this indicates that the implementing types will perform the comparison on instances of the same type (in this case, `f64` with `f64`).


Now, let's just implement it for the `f64` type:

```rust
impl ApproximateEq for f64 {
    fn approximate_eq(self, other: f64) -> bool {
        (self - other).abs() < <f64 as ApproximateEq>::EPSILON
    }
}
```

A notable concept to review here, is the reference to the `ApproximateEq::EPSILON` constant.

Something that may confuse programmers coming from other languages, is the role of trait constants: in Rust, constants defined in a trait constitute defaults, and, like trait methods, they must be referenced on the concrete types; in this case, on `f64`.

Now, there is a small complication in this specific implementation: `f64` already implements an `EPSILON` constant, which makes access to `ApproximateEq::EPSILON` ambiguous; see this:

```rust
impl ApproximateEq for f64 {
    fn approximate_eq(self, other: f64) -> bool {
        (self - other).abs() < f64::EPSILON
    }
}
```

Which `EPSILON` is this implementation referencing?

In order to make sure we reference the appropriate constant, we therefore need to disambiguate, via the so-called [Fully Qualified Syntax](https://doc.rust-lang.org/rust-by-example/trait/disambiguating.html): `<f64 as ApproximateEq>::EPSILON`.

That was all! Let's check an example:

```rust
fn test_comparison() {
    assert!(1.000000.approximate_eq(1.000001));
    assert!(! 1.0000.approximate_eq(1.0001));
}
```

Easy, and elegant! 🤩

## Implementing the solution on a trait

For the lulz, let's implement this logic as default method on a trait.

We define the trait as a simplistic representation of a bidimensional shape:

```rust
trait Shape {
    fn vertices(&self) -> Vec<(f64, f64)>;
}
```

First, we need to change the trait method to receive a reference; this is required for implementing the method on the trait, but it's important anyway, since it's intended to be generically implemented (e.g. on non-`Clone` types):

```rust
trait ApproximateEq {
    const EPSILON: f64 = 0.00001;

    fn approximate_eq(&self, other: &Self) -> bool; // see here
}

impl ApproximateEq for f64 {
    fn approximate_eq(&self, other: &f64) -> bool {
        (self - other).abs() < <f64 as ApproximateEq>::EPSILON
    }
}
```

Then, we implement it on the trait:

```rust
impl ApproximateEq for dyn Shape + '_ {
    fn approximate_eq(&self, other: &Self) -> bool {
        if self.vertices().len() != other.vertices().len() {
            return false;
        }

        self.vertices()
            .iter()
            .zip(other.vertices().iter())
            .all(|(vs, vo)| vs.0.approximate_eq(&vo.0) && vs.1.approximate_eq(&vo.1))
    }
}
```

Again, simple and functional!

Interestingly, we can override `EPSILON` for `dyn Shape` (and referencing it as `<dyn Shape as ApproximateEq>::EPSILON`), but in this example, it's not intended.

## Conclusion

By leveraging Rust functionalities, we've achieved a clean, generic solution to implementing approximate equality.

It's typical for Rust newcomers to perceive more advanced functionalities as obscure and/or complex. This is a fair point; languages like Rust may not be suited for all the use cases, or all the tastes.

However, for the cases where Rust is deemed an appropriate tool, it makes it possible to implement elegant solutions.
