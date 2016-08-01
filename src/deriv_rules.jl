


@runonce const DERIV_RULES =
    Dict{Tuple{Symbol,Vector{Type}, Int}, Tuple{Symbolic,Any}}()

# accepts expressions like `foo(x::Number, y::Matrix)`
# or
function typesof(ex::Expr)
    @assert ex.head == :call || ex.head == :(=)
    @assert reduce(&, [isa(exa, Expr) && exa.head == :(::)
                       for exa in ex.args[2:end]])
    return [eval(exa.args[2]) for exa in ex.args[2:end]]
end

# accepts expressions like `foo(x::Number, y::Matrix)`
function without_types(ex::Expr)
    @assert ex.head == :call || ex.head == :(=)
    @assert reduce(&, [isa(exa, Expr) && exa.head == :(::)
                       for exa in ex.args[2:end]])
    new_args = Symbol[exa.args[1] for exa in ex.args[2:end]]
    return Expr(ex.head, ex.args[1], new_args...)
end


macro deriv_rule(ex::Expr, idx::Int, dex::Any)
    if ex.head == :call
        op = ex.args[1]
        types = typesof(ex)
        ex_no_types = without_types(ex)
        DERIV_RULES[(op, types, idx)] = (ex_no_types, dex)
    elseif ex.head == :(=)
        types = [eval(exa.args[2]) for exa in ex.args]
        new_args = Symbol[exa.args[1] for exa in ex.args]
        ex_no_types = Expr(ex.head, new_args...)
        DERIV_RULES[(:(=), types[2:end], idx)] = (ex_no_types, dex)
    else
        error("Can only define derivative on calls and assignments")
    end
end

## function getrule(ex::Expr, types::Vector{DataType}, idx::Int)
##     return DERIV_RULES[(ex.args[1], types, idx)]
## end

function getrule(op::Symbol, types::Vector{DataType}, idx::Int)
    key = (op, types, idx)
    if haskey(DERIV_RULES, key)
        return DERIV_RULES[key]
    else
        error("Can't find derivation rule for $key")
    end
end

function applyrule(rule::Tuple{Expr, Any}, ex::Expr)
    return rewrite(ex, rule[1], rule[2])
end










@deriv_rule (x::Float64 ^ n::Int) 1 (n * x^(n-1))
@deriv_rule (a::Float64 ^ x::Int) 2 (log(a) * a^x)
@deriv_rule (x::Float64 + y::Float64) 1 x
@deriv_rule (x::Float64 + y::Float64) 2 y

@deriv_rule (x::Float64 = y::Float64) 1 1.
@deriv_rule (x::Int64 = y::Int64) 1 1.


# const GENERIC_MATCHERS = Set([:CONST, :NUMBER, :ARRAY])

# TODO: create function `find_rule()` that first tries to get rule
# by concrete type and then by its ancestors e.g.
# Floar64 -> AbstractFloat -> Real -> Number

# snippet: while t != Any println(t); t = super(t) end

# TODO: do we really need CONST matcher?


## derivative rules








