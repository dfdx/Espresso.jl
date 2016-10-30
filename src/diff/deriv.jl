
# diff_base.jl - common routines for ordinary symbolic and tensor differentiation

abstract AbstractDeriv

immutable Deriv
    ex::Any
end

function *(d1::Deriv, d2::Deriv)
    return Deriv(simplify(d1.ex * d2.ex))
end

function +(d1::Deriv, d2::Deriv)
    return Deriv(simplify(d1.ex + d2.ex))
end

expr(d::Deriv) = d.ex
to_expr(d::Deriv) = d.ex
Base.show(io::IO, d::Deriv) = print(io, expr(d))

abstract AbstractDiffRule

immutable DiffRule <: AbstractDiffRule
    pat::Expr        # pattern of expression to differentiate
    deriv::Deriv     # pattern of differentiation expression
end


const DIFF_PHS = Set([:x, :y, :z, :a, :b, :c, :m, :n])

@runonce const DIFF_RULES =
        Dict{Tuple{OpName, Vector{Type}, Int}, DiffRule}()


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
        DIFF_RULES[(op, types, idx)] = DiffRule(ex_no_types, Deriv(dex))
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
function apply_rule(rule::DiffRule, ex::Expr)
    deriv_ex = rewrite(ex, rule.pat, rule.deriv.ex; phs=DIFF_PHS)
    return Deriv(deriv_ex)
end


## register rule

"""
Register new differentiation rule for function `fname` with arguments
of `types` at index `idx`, return this new rule.
"""
function register_rule(fname::OpName, types::Vector{DataType}, idx::Int)    
    # TODO: check module
    f = eval(fname)
    args, ex = funexpr(f, types)
    ex = sanitize(ex)
    # TODO: replace `ones()` with `example_val()` that can handle arrays
    xs = [(arg, ones(T)[1]) for (arg, T) in zip(args, types)]
    dexs = rdiff(ex; inputs=Dict(xs))
    dex = dexs[args[idx]]
    fex = Expr(:call, fname, args...)
    new_rule = DiffRule(fex, Deriv(dex))
    DIFF_RULES[(fname, types, idx)] = new_rule
    return new_rule
end

## derivative (for primitive expressions)

function derivative(pex::Expr, types::Vector{DataType}, idx::Int;
                    mod=current_module())
    @assert pex.head == :call
    op = canonical(mod, pex.args[1])
    maybe_rule = find_rule(op, types, idx)
    rule = !isnull(maybe_rule) ? get(maybe_rule) : register_rule(op, types, idx)
    return apply_rule(rule, pex)
end

derivative(var::Symbol, types::Vector{DataType}, idx::Int) = Deriv(1)
