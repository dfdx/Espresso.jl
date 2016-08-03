



@runonce const DERIV_RULES =
        Dict{Tuple{Symbol,Vector{Type}, Int}, Tuple{Symbolic,Any}}()

# @runonce const DERIV_RULES = SearchTree()


macro deriv_rule(ex::Expr, idx::Int, dex::Any)
    if ex.head == :call
        op = ex.args[1]
        types = [eval(exa.args[2]) for exa in ex.args[2:end]]
        new_args = Symbol[exa.args[1] for exa in ex.args[2:end]]        
        ex_no_types = Expr(ex.head, ex.args[1], new_args...)
        DERIV_RULES[(op, types, idx)] = (ex_no_types, dex)
    elseif ex.head == :(=)
        types = [eval(exa.args[2]) for exa in ex.args]
        new_args = Symbol[exa.args[1] for exa in ex.args]
        ex_no_types = Expr(ex.head, new_args...)
        DERIV_RULES[(:(=), types, idx)] = (ex_no_types, dex)
    else
        error("Can only define derivative on calls and assignments")
    end
end


function type_ansestors{T}(t::Type{T})
    types = Type[]
    while t != Any
        push!(types, t)
        t = super(t)
    end
    push!(types, Any)
    return types
end


function find_rule(op::Symbol, types::Vector{DataType}, idx::Int)
    type_ans = map(type_ansestors, types)
    type_products = product(type_ans...)
    ks = [(op, [tp...], idx) for tp in type_products]
    for k in ks
        if haskey(DERIV_RULES, k)
            return DERIV_RULES[k]
        end
    end
    error("Can't find differentiation rule for ($op, $types, $idx)")
end


function apply_rule(rule::Tuple{Expr, Any}, ex::Expr)
    return rewrite(ex, rule[1], rule[2])
end





@deriv_rule (x::Number ^ n::Int) 1 (n * x^(n-1))
@deriv_rule (a::Number ^ x::Number) 2 (log(a) * a^x)
@deriv_rule (x::Number + y::Number) 1 x
@deriv_rule (x::Number + y::Number) 2 y

@deriv_rule (x::Number = y::Number) 1 1.
@deriv_rule (x::AbstractArray = y::AbstractArray) 1 1.


# const GENERIC_MATCHERS = Set([:CONST, :NUMBER, :ARRAY])

# TODO: create function `find_rule()` that first tries to get rule
# by concrete type and then by its ancestors e.g.
# Floar64 -> AbstractFloat -> Real -> Number

# snippet: while t != Any println(t); t = super(t) end

# TODO: do we really need CONST matcher?


## derivative rules








