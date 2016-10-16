
# diff_base.jl - common routines for ordinary symbolic and tensor differentiation

abstract AbstractDeriv

immutable Deriv
    dvar::Symbol
    wrt::Symbol
    ex::Any
end

function *(d1::Deriv, d2::Deriv)
    # assert chain rule (we might not need it, but let's try)
    @assert d1.wrt == d2.dvar 
    return Deriv(d1.dvar, d2.wrt, d1.ex * d2.ex)
end

function +(d1::Deriv, d2::Deriv)
    @assert d1.dvar == d2.dvar && d1.wrt == d2.wrt
    return Deriv(d1.dvar, d1.wrt, d1.ex + d2.ex)
end


abstract AbstractDiffRule

immutable DiffRule <: AbstractDiffRule
    ex::Expr        # pattern of expression to differentiate
    idx::Int        # index of argument to differentiate against
    deriv::Deriv    # pattern of differentiation expression
end


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


