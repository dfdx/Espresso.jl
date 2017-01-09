# Espresso

[![Build Status](https://travis-ci.org/dfdx/Espresso.jl.svg?branch=master)](https://travis-ci.org/dfdx/Espresso.jl)

Expression transformation package. 

## Expression parsing and rewriting

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

See also `matchingex`.  
See also `findex`.

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

See also `tryrewrite`.

### Expression simplification

`simplify` - simplify numeric expression if possible.

```
simplify(:(2 - 1))
## ==> 1
simplify(:(1 * (2x^1)))
## ==> :(2x)
```

## Einstein indexing notation

Espresso.jl also supports expressions in Einstein indexing notation and is mostly compatible with [Einsum.jl](https://github.com/ahwillia/Einsum.jl). The most important functions are:

`to_einstein` - convert vectorized expression to Einstein notation.

```
to_einstein(:(W*x + b); W=rand(3,4), x=rand(4), b=rand(3))
## ==> quote
## ==>    tmp1[i] = W[i,k] * x[k]
## ==>    tmp2[i] = tmp1[i] + b[i]
## ==> end
```

Here `W=rand(3,4)`, `x=rand(4)` and `b=rand(3)` are _example values_ - anything that has the same type and dimensions as real expected values.

`from_einstein` - convert an expression in Einstein notation to vectorized form if possible.

```
from_einstein(:(W[i,k] * x[k] + b[i]))
## ==> quote  # REPL[7], line 2:
## ==>     tmp1 = W * x # REPL[7], line 3:
## ==>     tmp2 = tmp1 + b
## ==> end
```

## ExGraph

On low-level many functions of Espresso.jl use `ExGraph` - expression graph, represented as a topologically sorted list of primitive expression. Example:

```
g = ExGraph(:(W*x + b); W=rand(3,4), x=rand(4), b=rand(3))
## ==> ExGraph
## ==>   ExNode{input}(W = W | <Array{Float64,2}>)
## ==>   ExNode{input}(x = x | <Array{Float64,1}>)
## ==>   ExNode{input}(b = b | <Array{Float64,1}>)
## ==>   ExNode{call}(tmp1 = W * x | nothing)
## ==>   ExNode{call}(tmp2 = tmp1 + b | nothing)
```

The main advantage of using such representation is that each node represents exactly one simple enough expression such as assignment or function call. For example, `to_einstein` and `from_einstein` both use `ExGraph` to find rule for transforming between two notations.