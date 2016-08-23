
# diff_rules.jl - differentiation rules for basic operations.
#
# The most important macors and methods here are:
#
# * `@diff_rule` - define new differentiation rule
# * `find_rule` - find differentiation rule
# * `apply_rule` - rewrite expression according to the rule
#
# Differentiation procedure itself is described in `rdiff.jl`.

const DIFF_PHS = Set([:x, :y, :z, :a, :b, :c, :m, :n])

@runonce const DIFF_RULES =
        Dict{Tuple{OpName,Vector{Type}, Int}, Tuple{Symbolic,Any}}()


opname(mod, op) = canonical(mod, op)

"""
Define new differentiation rule. Arguments:

 * `ex` - original expression in a form `func(arg1::Type1, arg2::Type2, ...)`
 * `idx` - index of argument to differentiate over
 * `dex` - expression of corresponding derivative

Example:

    @diff_rule *(x::Number, y::Number) 1 y

Which means: derivative of a product of 2 numbers w.r.t. 1st argument 
is a second argument. 

Note that rules are always defined as if arguments were ordinary variables
and not functions of some other variables, because this case will be
automatically handled by chain rule in the differentiation engine. 

"""
macro diff_rule(ex::Expr, idx::Int, dex::Any)
    if ex.head == :call
        # TODO: check this particular use of `current_module()`
        op = opname(current_module(), ex.args[1])
        types = [eval(exa.args[2]) for exa in ex.args[2:end]]
        new_args = Symbol[exa.args[1] for exa in ex.args[2:end]]
        ex_no_types = Expr(ex.head, ex.args[1], new_args...)
        DIFF_RULES[(op, types, idx)] = (ex_no_types, dex)
    else
        error("Can only define derivative on calls")
    end
end


"""
Find differentiation rule for `op` with arguments of `types`
w.r.t. `idx`th argument. Example:

    rule = find_rule(:*, [Int, Int], 1)

Which reads as: find rule for product of 2 Ints w.r.t. 1st argument.

In addition to the types passed, rules for all combinations of all their
ansestors (as defined by `type_ansestors()`) will be checked.

Rule itself is an opaque object containing information needed for derivation
and guaranted to be compatible with `apply_rule()`.
"""
function find_rule(op::OpName, types::Vector{DataType}, idx::Int)
    type_ans = map(type_ansestors, types)
    type_products = product(type_ans...)
    ks = [(op, [tp...], idx) for tp in type_products]
    for k in ks
        if haskey(DIFF_RULES, k)
            return Nullable(DIFF_RULES[k])
        end
    end
    return Nullable()
end

"""
Apply rule retrieved using `find_rule()` to an expression. 
"""
function apply_rule(rule::Tuple{Expr, Any}, ex::Expr)
    return rewrite(ex, rule[1], rule[2]; phs=DIFF_PHS)
end


## basic rules

@diff_rule (-x::Number) 1 -1

# product

@diff_rule *(x::Number, y::Number) 1 y
@diff_rule *(x::Number, y::AbstractArray) 1 sum(y)
@diff_rule *(x::AbstractArray, y::Number) 1 y
@diff_rule *(x::AbstractArray, y::AbstractArray) 1 y'

@diff_rule *(x::Number, y::Number) 2 x
@diff_rule *(x::Number, y::AbstractArray) 2 x
@diff_rule *(x::AbstractArray, y::Number) 2 sum(x)
@diff_rule *(x::AbstractArray, y::AbstractArray) 2 x'

# elementwise product

@diff_rule .*(x::Number, y::Number) 1 y
@diff_rule .*(x::Number, y::AbstractArray) 1 sum(y)
@diff_rule .*(x::AbstractArray, y::Number) 1 y
@diff_rule .*(x::AbstractArray, y::AbstractArray) 1 y

@diff_rule .*(x::Number, y::Number) 2 x
@diff_rule .*(x::Number, y::AbstractArray) 2 x
@diff_rule .*(x::AbstractArray, y::Number) 2 sum(x)
@diff_rule .*(x::AbstractArray, y::AbstractArray) 2 x

# other arithmetic operations

@diff_rule (x::Number ^ n::Int) 1 (n * x^(n-1))
@diff_rule (a::Number ^ x::Number) 2 (log(a) * a^x)

@diff_rule (x::Number / y::Number) 1 (x / y)
@diff_rule (x::AbstractArray / y::Number) 1 x ./ y
@diff_rule (n::Number / x::Real) 2 (-n * x ^ -2)
@diff_rule (x::AbstractArray / y::Real) 2 (sum(-x .* y) / (y * y))

@diff_rule (x::Any + y::Any) 1 1
@diff_rule (x::Any + y::Any) 2 1
@diff_rule (x::Any + y::Any + z::Any) 1 1
@diff_rule (x::Any + y::Any + z::Any) 2 1
@diff_rule (x::Any + y::Any + z::Any) 3 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 1 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 2 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 3 1
@diff_rule (w::Any + x::Any + y::Any + z::Any) 4 1

@diff_rule (x::Any .+ y::Any) 1 1
@diff_rule (x::Any .+ y::Any) 2 1

@diff_rule (x::Any - y::Any) 1 1
@diff_rule (x::Any - y::Any) 2 -1

@diff_rule (x::Any .- y::Any) 1 1
@diff_rule (x::Any .- y::Any) 2 -1

@diff_rule sum(x::Number) 1 1
@diff_rule sum(x::AbstractArray) 1 ones(size(x))

# dot product

@diff_rule dot(x::Number, y::Number) 1 y
@diff_rule dot(x::Number, y::Number) 2 x

@diff_rule vecdot(x::AbstractVector, y::AbstractVector) 1 y
@diff_rule vecdot(x::AbstractVector, y::AbstractVector) 2 x

@diff_rule dot(x::AbstractArray, y::AbstractArray) 1 y
@diff_rule dot(x::AbstractArray, y::AbstractArray) 2 x

# trigonomeric functions

@diff_rule sin(x::Number) 1 cos(x)
@diff_rule sin(x::AbstractArray) 1 cos(x)
@diff_rule cos(x::Number) 1 -sin(x)
@diff_rule cos(x::AbstractArray) 1 -sin(x)

@diff_rule tan(x::Number) 1 (1. + tan(x)  * tan(x))
@diff_rule tan(x::AbstractArray) 1 (1. + tan(x) .* tan(x))

@diff_rule sinh(x::Number) 1 cosh(x)
@diff_rule sinh(x::AbstractArray) 1 cosh(x)

@diff_rule cosh(x::Number) 1 sinh(x)
@diff_rule cosh(x::AbstractArray) 1 sinh(x)

@diff_rule tanh(x::Number) 1 (1. - tanh(x)  * tanh(x))
@diff_rule tanh(x::AbstractArray) 1 (1. - tanh(x) .* tanh(x))

@diff_rule asin(x::Number) 1 (1 / sqrt(1 - x*x))
@diff_rule asin(x::AbstractArray) 1 (1 ./ sqrt(1 - x.*x))

@diff_rule acos(x::Number) 1 (1  / sqrt(1 - x *x))
@diff_rule acos(x::AbstractArray) 1 (-1 ./ sqrt(1 - x.*x))

@diff_rule atan(x::Number) 1 (1  / (1 + x*x))
@diff_rule atan(x::AbstractArray) 1 (1 ./ (1 + x.*x))

# sqrt

@diff_rule sqrt(x::Number) 1 (0.5 * x^(-0.5))
@diff_rule sqrt(x::AbstractVector) 1 (0.5 .* x .^ (-0.5))

# exp, log

@diff_rule exp(x::Number) 1 exp(x)
@diff_rule exp(x::AbstractArray) 1 exp(x)

@diff_rule log(x::Number) 1 (1/x)

# abs

@diff_rule abs(x::Number) 1 (sign(x) * x)
@diff_rule abs(x::AbstractArray) 1 (sign(x) .* x)

# min, max

@diff_rule max(x::Number, y::Number) 1 (x > y) * x
@diff_rule max(x::Number, y::Number) 2 (y > x) * y

@diff_rule min(x::Number, y::Number) 1 (x < y) * x
@diff_rule min(x::Number, y::Number) 2 (y < x) * y

@diff_rule sign(x::Any) 1 0.

# transpose

@diff_rule transpose(x::Number) 1 1
@diff_rule transpose(x::AbstractArray) 1 transpose(ones(size(x)))

@diff_rule size(x::Any) 1 0.
@diff_rule size(x::Any, y::Any) 1 0.
@diff_rule size(x::Any, y::Any) 2 0.
