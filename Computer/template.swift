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
*
fun [] = main()
{
  x = 24
  y = 42
  if(x > y) x = x-y
  else y = y-x
  if(x ! y) goto -2
  printn x 'is gcd'
}
*
n = x*cos(t)-y*sin(t)
*
if(i < 5) goto -2
else print 'expired'
*
for(k=1; k<5; k+=2) {
// , can also be used as
// separator in place of ;
}
*
print x 'is prime'
-------------------
fun [] = main()
{
  fun [m,i] = prime(n)
  {
    i = 2
    m = n%i
    if(m = 0) return
    q = sqrt(n)
    q = ceil(q)
    for(j=3; j<q+1; j+=2) {
      i = j
      m = n%i
      if(m = 0) return
    }
  }

  for(j=9; j<101; j+=2) {
    [d,k] = prime(j)
    if(d=0) printn k 'factor'
    else printn 'prime'
  }
}
*
-- What is not included --
1. Matrices!
2. Type system!
3. Complex expressions!
4. String implementation!
--------------------------

"""
