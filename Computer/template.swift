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
     ? "Solution" x1 x2
  }
}
fun <m,i>= prime(n) {
    i : 2
    m : n%i
    if m = 0 { return m i }
    q : sqrt(n)
    q : ceil(q)
    for j:3 to q step 2 {
      i : j
      m : n%i
      if m = 0 { return m i }
    }
    return m i
}

fun <> = main() {
  for j:9 to 100 step 2 {
    <d,k> : prime(j)
    if d = 0 { ? j "has factor" k }
    else { ? j "is a prime" }
  }
}

fun <> = main() {
 hunza:  42000
 minapin: 16000
 chillas: 7000
 skardu: 24000
 khaplu: 18000
 ? hunza + minapin + chillas + skardu + khaplu
}
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
-------------------
-- What is not included --
1. Matrices!
2. Type system!
3. String implementation!
--------------------------
"""
