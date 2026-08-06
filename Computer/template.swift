//
//  template.swift
//  Computer
//
//  Created by Home on 7/26/19.
//  Copyright © 2019 Home. All rights reserved.
//
//  A reference sheet of working Shalimar, kept in source rather than wired to a
//  view: every snippet below runs as written under the 3.0 core. When the language
//  changes, this file changes with it - a snippet that no longer parses is worse
//  than no snippet at all, because it is the first thing anyone copies.
//

import Foundation

let templateText = """
\u{1F1F5}\u{1F1F0}
©2019 G R Akhtar, Islamabad
All rights reserved
-------------------
? "is prime" x
-------------------
// shape - row, col, dim(n)
fun <> = main() {
  real A[3][4]
  int  C[2][3][5]
  real v[10]

  ? "rows" A.row "cols" A.col
  ? "the same two axes" A.dim(0) A.dim(1)
  ? "third axis" C.dim(2)
  ? "a vector has no columns" v.col
}
// count loop - for i < n is 'for i : 0 to n - 1'
fun <> = fill(M[][]: real) {
  for i < M.row {
    for j < M.col {
      M[i][j] : i * 10 + j
    }
  }
}

fun <> = main() {
  real A[2][3]
  fill(A)
  ? A
}
// precision - prec(n) runs -1 to 24, -1 restores the default
fun <> = main() {
  real tol : 1e-20

  ? prec(22) "tol" tol
  ? prec(3) 1./3.
  ? prec(-1) 1./3.
}
// conversions - int() drops the fraction, real() is exact
fun <> = main() {
  real x : 2.7

  ? int(x) int(0.-x)
  ? real(20)
}
// quadratic
fun <> = main() {
  a : 1.
  b : 2.
  c : 1.
  d : b^2-4*a*c
  if d < 0 {
    ? "no real roots"
  }
  else {
     d : sqrt(d)
     x1 : (-b-d)/(2.*a)
     x2 : (-b+d)/(2.*a)
     ? "Solution" x1 x2
  }
}
// prime
fun <int,int> = prime(n: int) {
    int i : 2
    int m : n%i
    if m = 0 { return (m, i) }
    int q : int(ceil(sqrt(n)))
    for j:3 to q step 2 {
      i : j
      m : n%i
      if m = 0 { return (m, i) }
    }
    return (m, i)
}

fun <> = main() {
  for j:9 to 100 step 2 {
    <d,k> : prime(j)
    if d = 0 {
      ? j "has factor" k
    }
    else {
      ? j "is a prime"
    }
  }
}
// invert
fun <real> = invert(a[][]: real) {
  real tol : 1e-30
  real det : 1.0
  real r : 0.0

  for i < a.row {
    det : det * a[i][i]

    if abs(det) < tol | abs(det) = tol {
      if a[i][i] = 0.0 { return det }
      det : tol
    }

    r : 1.0 / a[i][i]
    a[i][i] : 1.0
    for j < a.col {
      a[i][j] : r * a[i][j]
    }

    for k < a.row {
      if k != i & a[k][i] != 0.0 {
        r : a[k][i]
        a[k][i] : 0.0
        for j < a.col {
          a[k][j] -: r * a[i][j]
        }
      }
    }
  }

  return det
}

fun <> = main() {
  real m[3][3] : {{4.0, 7.0, 2.0},
                  {3.0, 6.0, 1.0},
                  {2.0, 5.0, 3.0}}
  real s[3][3] : {{1.0, 2.0, 3.0},
                  {2.0, 4.0, 6.0},
                  {1.0, 1.0, 1.0}}
  real ab[2][3] : {{2.0, 1.0, 1.0},
                   {1.0, 3.0, 2.0}}
  real d : 0.0

  d : invert(m)
  ? "inverse, det" d
  ? m

  d : invert(s)
  ? "singular, det" d

  d : invert(ab)
  ? "solved, det" d
  ? ab
}
-------------------
-- What is not included --
1. Arrays cannot be returned in <> - pass one in and fill it, it is a reference
2. No pi or e constants - write the number
3. No string functions - char[] holds text, nothing splits or joins it
4. No input - a program only prints
--------------------------
"""
