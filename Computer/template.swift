//
//  template.swift
//  Computer
//
//  Created by Home on 7/26/19.
//  Copyright © 2019 Home. All rights reserved.
//

import Foundation

let templateText = """
\u{1F1F5}\u{1F1F0}
©2019 G R Akhtar, Islamabad
All rights reserved
-------------------
? "is prime" x
-------------------
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
fun <m,i>= prime(n) {
    int i : 2
    int m : n%i
    if m = 0 { return (m, i) }
    q : sqrt(n)
    q : ceil(q)
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
// quadratic
fun <> = main() {
  a : 1
  b : 2
  c : 1
  d : b^2-4*a*c
  if d < 0 {
    ? "no real roots"
  }
  else {
     d : sqrt(d)
     x1 : (-b-d)/(2*a)
     x2 : (-b+d)/(2*a)
     ? x1 x2
  }
}
// invert
fun <real> = invert(a[][]: real) {
  real tol : pow(10.0, 0.0 - 30.0)
  real det : 1.0
  real r : 0.0
  int  n : len(a)
  int nc : len(a[0])

  for i : 0 to n - 1 {
    det : det * a[i][i]

    if abs(det) < tol | abs(det) = tol {
      if a[i][i] = 0.0 { return det }
      det : tol
    }

    r : 1.0 / a[i][i]
    a[i][i] : 1.0
    for j : 0 to nc - 1 {
      a[i][j] : r * a[i][j]
    }

    for k : 0 to n - 1 {
      if k != i & a[k][i] != 0.0 {
        r : a[k][i]
        a[k][i] : 0.0
        for j : 0 to nc - 1 {
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
1. Matrices!
2. Type system!
3. String implementation!
--------------------------
"""
