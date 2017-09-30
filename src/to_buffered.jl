
# to_buffered.jl - transform ExGraph to buffered/in-place operations

const Num = Number
const Vec = AbstractVector
const Mat = AbstractMatrix

const TO_BUFFERED_VEC_PHS = Set([:X, :Y, :Z])

const TO_BUFFERED_VEC_RULES = [
    [Mat, Mat] => :(Z = X * Y) => :(A_mul_B!(Z, X, Y)),
    [Mat, Mat] => :(Z = X' * Y) => :(At_mul_B!(Z, X, Y)),
    [Mat, Mat] => :(Z = X * Y') => :(A_mul_Bt!(Z, X, Y)),
]


function to_buffered(g::ExGraph)
    evaluate!(g)
    g = expand_fixed_sequences(g)
    g = fuse_broadcasting(g)
    res = :(begin end)
    for nd in g.tape
        if getcategory(nd) != :input
            vex = to_buffered(g, nd)
            # push!(res.args, simplify(subs_size(vex, sizes)))
            push!(res.args, vex)
        end
    end
    res = subs_bcast_with_dot(sanitize(res))
    return res
end


function to_buffered(g::ExGraph, nd::Union{ExNode{:call}, ExNode{:bcast}, ExNode{:opaque}})
    ex = expand_const(g, to_expr(nd)) |> simplify
    if isa(nd, ExNode{:call}) && !iscall(ex.args[2])
        return to_buffered(g, convert_call(g, nd))
    end
    # try patterns
    dep_vals = [getvalue(g[dep]) for dep in dependencies(nd)]
    for (types, (pat, rpat)) in TO_BUFFERED_VEC_RULES
        if all(isa(val, T) for (val, T) in zip(dep_vals, types))
            pat = sanitize(pat)
            rex = tryrewrite(ex, pat, rpat; phs=TO_BUFFERED_VEC_PHS, allow_ex=false)
            if !isnull(rex)
                return get(rex)
            end
        end
    end
    # try broadcasting
    if is_bcast_vec(nd)
        lhs_is_scalar = isa(getvalue(nd), Number)
        return make_elementwise(without_indices(to_expr(nd));
                                lhs_is_scalar=lhs_is_scalar)
    end
    # if LHS is an array, use .= instead of =
    if isa(getvalue(nd), AbstractArray)
        rex = to_expr(nd)
        rex.head = :.=
        return rex
    end
    return to_expr(nd)
end


function to_buffered(g::ExGraph, nd::ExNode{:ctor})    
    ex = to_expr_kw(nd)
    insert!(ex.args[2].args, 3, :mem)
    insert!(ex.args[2].args, 4, QuoteNode(varname(nd)))
    return ex
end


function to_buffered(g::ExGraph, nd::ExNode)
    return to_expr(nd)
end
