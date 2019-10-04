# Espresso

[![Build Status](https://travis-ci.org/dfdx/Espresso.jl.svg?branch=master)](https://travis-ci.org/dfdx/Espresso.jl)

Expression transformation package. 

## Symbolic manipulation

Espresso provides functions for finding, matching, substituting and rewriting Julia AST. A few examples:

Match power expression and extract its first argument

```julia
pat = :(_x ^ 2)  # anything starting with `_` is a placeholder, placeholder matches everything
ex = :(A ^ 2)
matchex(pat, ex)
# ==> Dict{Symbol,Any} with 1 entry:
# ==>   :_x => :A    -- placeholder _x captured symbol :A
```

Find all function calls with any number of arguments:
```julia
pat = :(_f(_a...))    # `_a...` will match 0 or more arguments
ex = quote
    x = foo(3, 5)
    y = bar(x)
    z = baz(y)
end

findex(pat, ex)
# ==> 3-element Array{Any,1}:
# ==>  :(foo(3, 5))
# ==> :(bar(x))   
# ==>  :(baz(y)) 
```
Substitute symbol `y` with `quux(x)`:

```julia
ex = :(z = 2x + y)
subs(ex, Dict(:y => :(quux(x))))
# ==> :(z = 2x + quux(x))
```

Rewrite all function calls with corresponding broadcasting: 

```julia
ex = :(z = foo(x) + bar(y))     # take this expression
pat = :(_f(_a...))              # match recursively to this pattern
rpat = :(_f.(_a...))             # and rewrite to this pattern
rewrite_all(ex, pat, rpat)
# ==> :(z = (+).(foo.(x), bar.(y)))
```
See [rewrite.jl](https://github.com/dfdx/Espresso.jl/blob/master/src/rewrite.jl) for more expression transformation functions and their parameters.

## Expression graph

Sometimes we need more sophisticated transformations including those depending on argument types. Espresso can parse expressions into a graph of basic calls and assignments using `ExGraph` type, e.g.:

```julia
ex = :(z = x ^ 2 * (y + x ^ 2))
g = ExGraph(ex; x=3.0, y=2.0);     # `x` and `y` are example values from which ExGraphs learns types of these vars
evaluate!(g)                       # evaluate all expressions to fill values of intermediate nodes
g
# ==> ExGraph
# ==>   ExNode{input}(x = x | 3.0)
# ==>   ExNode{input}(y = y | 2.0)
# ==>   ExNode{constant}(tmp390 = 2 | 2)
# ==>   ExNode{call}(tmp391 = x ^ tmp390 | 9.0)
# ==>   ExNode{constant}(tmp392 = 2 | 2)
# ==>   ExNode{call}(tmp393 = x ^ tmp392 | 9.0)
# ==>   ExNode{call}(tmp394 = y + tmp393 | 11.0)
# ==>   ExNode{call}(z = tmp391 * tmp394 | 99.0)
```
Such representation, although somewhat cryptic, is more flexible. For example, using it we can easily get rid of common subexpressions (`x ^ 2`):

```julia
g2 = eliminate_common(g)
# ==> ExGraph
# ==>   ExNode{input}(x = x | 3.0)
# ==>   ExNode{input}(y = y | 2.0)
# ==>   ExNode{constant}(tmp390 = 2 | 2)
# ==>   ExNode{call}(tmp391 = x ^ tmp390 | 9.0)
# ==>   ExNode{call}(tmp394 = y + tmp391 | 11.0)
# ==>   ExNode{call}(z = tmp391 * tmp394 | 99.0)
```
`to_expr` and `to_expr_kw` construct a Julia expression back from `ExGraph`:

```julia
to_expr_kw(g2)
# ==> quote    
# ==>     tmp390 = 2
# ==>     tmp391 = x ^ tmp390
# ==>     tmp394 = y + tmp391
# ==>     z = tmp391 * tmp394
# ==> end
```


## (Somewhat outdated) documentation

[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://dfdx.github.io/Espresso.jl/stable)
[![](https://img.shields.io/badge/docs-latest-blue.svg)](https://dfdx.github.io/Espresso.jl/latest)

