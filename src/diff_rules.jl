



@runonce const DIFF_RULES =
        Dict{Tuple{Symbol,Vector{Type}, Int}, Tuple{Symbolic,Any}}()

# @runonce const DIFF_RULES = SearchTree()


macro diff_rule(ex::Expr, idx::Int, dex::Any)
    if ex.head == :call
        op = ex.args[1]
        types = [eval(exa.args[2]) for exa in ex.args[2:end]]
        new_args = Symbol[exa.args[1] for exa in ex.args[2:end]]        
        ex_no_types = Expr(ex.head, ex.args[1], new_args...)
        DIFF_RULES[(op, types, idx)] = (ex_no_types, dex)
    ## elseif ex.head == :(=)
    ##     types = [eval(exa.args[2]) for exa in ex.args]
    ##     new_args = Symbol[exa.args[1] for exa in ex.args]
    ##     ex_no_types = Expr(ex.head, new_args...)
    ##     DIFF_RULES[(:(=), types, idx)] = (ex_no_types, dex)
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
        if haskey(DIFF_RULES, k)
            return DIFF_RULES[k]
        end
    end
    error("Can't find differentiation rule for ($op, $types, $idx)")
end


function apply_rule(rule::Tuple{Expr, Any}, ex::Expr)
    return rewrite(ex, rule[1], rule[2])
end





@diff_rule (x::Number ^ n::Int) 1 (n * x^(n-1))
@diff_rule (a::Number ^ x::Number) 2 (log(a) * a^x)

@diff_rule (x::Number * y::Number) 1 y
@diff_rule (x::Number * y::Number) 2 x

@diff_rule (x::Number + y::Number) 1 1
@diff_rule (x::Number + y::Number) 2 1
@diff_rule (x::Number + y::Number + z::Number) 1 1
@diff_rule (x::Number + y::Number + z::Number) 2 1
@diff_rule (x::Number + y::Number + z::Number) 3 1
@diff_rule (w::Number + x::Number + y::Number + z::Number) 1 1
@diff_rule (w::Number + x::Number + y::Number + z::Number) 2 1
@diff_rule (w::Number + x::Number + y::Number + z::Number) 3 1
@diff_rule (w::Number + x::Number + y::Number + z::Number) 4 1


@diff_rule (x::Number - y::Number) 1 1
@diff_rule (x::Number - y::Number) 2 -1

@diff_rule sin(x::Number) 1 cos(x)
@diff_rule cos(x::Number) 1 sin(x)








