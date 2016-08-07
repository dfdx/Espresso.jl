# Hydra

[![Build Status](https://travis-ci.org/dfdx/Hydra.jl.svg?branch=master)](https://travis-ci.org/dfdx/Hydra.jl)

Symbolic transformations and hybrid differentiation.

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

### Hybrid differentiation

`rdiff` - find derivatives of an expression w.r.t. input params. Input parameters
should be initialized with example values so that algorithm could infer their type
and other metadata.

```
rdiff(:(x1*x2 + sin(x1)), x1=1., x2=1.)
# ==> [:(x2 + cos(x1)), :x1]
```

This is a hybrid algorithm in sense that it uses techniques from
automatic differentiation (AD), but produces symbolic expression for each input.

Differentiation algorithm is heavily inspired by [ReverseDiffSource.jl][1],
but has a number of differences in implementation and capabilities.



[1]: https://github.com/JuliaDiff/ReverseDiffSource.jl