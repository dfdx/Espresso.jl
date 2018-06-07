
# to_inplace.jl - transform ExGraph to buffered/in-place operations

const Num = Number
const Vec = AbstractVector
const Mat = AbstractMatrix

const INPLACE_PHS = Set([:u, :v, :w, :x, :y, :z, :X, :Y, :Z])

const INPLACE_RULES = [
    Type[Mat, Mat] => :(Z = X' * Y) => :(mul!(Z, transpose(X), Y)),
    Type[Mat, Mat] => :(Z = X * Y') => :(mul!(Z, X, transpose(Y))),
    Type[Mat, Mat] => :(Z = X * Y) => :(mul!(Z, X, Y)),    
]


function to_inplace(g::ExGraph)
    evaluate!(g)
    g = expand_fixed_sequences(g)
    g = fuse_broadcasting(g)
    res = :(begin end)
    for nd in g.tape
        if getcategory(nd) != :input
            vex = to_inplace(g, nd)
            # push!(res.args, simplify(subs_size(vex, sizes)))
            push!(res.args, vex)
        end
    end
    res = subs_bcast_with_dot(sanitize(res))
    return res
end


function to_inplace(g::ExGraph, nd::Union{ExNode{:call}, ExNode{:bcast}, ExNode{:opaque}})
    ex = expand_const(g, to_expr_kw(nd)) |> simplify
    if isa(nd, ExNode{:call}) && !iscall(ex.args[2])
        return to_inplace(g, convert_call(g, nd))
    end
    # try patterns
    dep_vals = [getvalue(g[dep]) for dep in dependencies(nd)]
    for (types, (pat, rpat)) in INPLACE_RULES
        if all(isa(val, T) for (val, T) in zip(dep_vals, types))
            pat = sanitize(pat)
            rex = tryrewrite(ex, pat, rpat; phs=INPLACE_PHS)
            if rex != nothing
                return rex
            end
        end
    end
    # try broadcasting
    if is_bcast_vec(nd)
        lhs_is_scalar = isa(getvalue(nd), Number)
        return make_elementwise(to_expr_kw(nd); lhs_is_scalar=lhs_is_scalar)
    end
    # if LHS is an array, use .= instead of =
    if isa(getvalue(nd), AbstractArray)
        rex = to_expr_kw(nd)
        rex.head = :.=
        return rex
    end
    return to_expr_kw(nd)
end


function to_inplace(g::ExGraph, nd::ExNode{:ctor})
    ex = to_expr_kw(nd)
    insert!(ex.args[2].args, 3, :mem)
    insert!(ex.args[2].args, 4, QuoteNode(varname(nd)))
    return ex
end


function to_inplace(g::ExGraph, nd::ExNode)
    return to_expr_kw(nd)
end


to_buffered = to_inplace


## @inplacerule


# TODO: copied from XGrad, fix
isparameters(a) = isa(a, Expr) && a.head == :parameters

function without_types(pat)
    rpat = copy(pat)
    for i=2:length(rpat.args)
        a = rpat.args[i]
        if !isparameters(a)  # parameters aren't modified
            rpat.args[i] = isa(a, Expr) ? a.args[1] : a
        end
    end
    return rpat
end

function get_arg_names(pat)
    return [isa(a, Expr) ? a.args[1] : a for a in pat.args[2:end] if !isparameters(a)]
end

function get_arg_types(pat)
    return [isa(a, Expr) ? eval(Base, a.args[2]) : Any for a in pat.args[2:end] if !isparameters(a)]
end



function add_inplace_rule(mod::Module, tpat, rpat)
    @assert tpat.head == :(=)
    @assert rpat.head == :call
    op = canonical(mod, tpat.args[2].args[1])
    rop = canonical(mod, rpat.args[1])
    types = get_arg_types(tpat.args[2])
    pat = :($(tpat.args[1]) = $(without_types(tpat.args[2])))
    # replace function names with canonical names
    pat = subs(pat, Dict(tpat.args[2].args[1] => op))
    rpat = subs(rpat, Dict(rpat.args[1] => rop))
    rule = types => pat => rpat
    push!(INPLACE_RULES, rule)
end


macro inplacerule(tpat, rpat)
    mod = @__MODULE__
    add_inplace_rule(mod, tpat, rpat)
    nothing
end
