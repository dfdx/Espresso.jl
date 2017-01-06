# Espresso

[![Build Status](https://travis-ci.org/dfdx/Espresso.jl.svg?branch=master)](https://travis-ci.org/dfdx/Espresso.jl)

Expression transformations.

### Expression matching

`matchex` - match expression by pattern, extract matching elements.
Elements of expression are matched to placeholders - symbols in pattern
that start with '_' or any symbols passed in `phs` parameter.

```
matchex(:(_x^2), :(u^2))
# ==> Nullable(Dict{Symbol,Any}(:_x=>:u))
matchex(:(x^n), :(u^2); phs=Set([:x, :n]))
# ==> Nullable(Dict{Symbol,Any}(:x=>:u,:n=>2))
```


### Expression substitution

`subs` - substitute elements of in expression according to substitution table:

```
ex = :(x ^ n)
subs(ex, x=2)
# ==> :(2 ^ n)
```

### Expression rewriting

`rewrite` - rewrite an expression matching it to a pattern and replacing
corresponding placeholders in substitution expression. 

```
ex = :(u ^ v)
pat = :(_x ^ _n)
subex = :(_n * _x ^ (_n - 1))
rewrite(ex, pat, subex)
# ==> :(v * u ^ (v - 1))
```

### Expression simplification

`simplify` - simplify numeric expression if possible

```
simplify(:(2 - 1))
## ==> 1
simplify(:(1 * (2x^1)))
## ==> :(2x)
```

