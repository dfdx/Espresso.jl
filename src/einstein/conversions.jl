
# from vectorized to Einstein notation

const TO_EINSTEIN_RULES =
    OrderedDict((:sum, [0]) => (:(sum(X)), :(X[i] * I[i])),
                (:*, [0, 0]) => (:(X * Y), :(X[] * Y[])),
                (:*, [1, 1]) => (:(X * Y), :(X[i] * Y[i])),
                (:*, [2, 1]) => (:(X * Y), :(X[i,k] * Y[k])),
                (:*, [1, 2]) => (:(X * Y), :(X[k] * Y[k,j])),
                (:*, [2, 2]) => (:(X * Y), :(X[i,j] * Y[k,j])))

function to_einstein(ex::Expr; xs...)
    g = ExGraph(ex; xs...)
    forward_pass(g, ex)
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, to_einstein(g, nd))
        end
    end
    return res
end


function to_einstein(g::ExGraph, nd::ExNode{:call})
    ex = expr(nd)
    op = ex.args[1]
    dep_dims = [ndims(g[dep].val) for dep in dependencies(nd)]
    if haskey(TO_EINSTEIN_RULES, (op, dep_dims))
        pat, subex = TO_EINSTEIN_RULES[(op, dep_dims)]
        matched = tryrewrite(ex, pat, subex; phs=TDIFF_PHS)
        if !isnull(matched)
            new_ex = get(matched)
            varidxs = forall_indices(new_ex)
            return Expr(:(=), Expr(:ref, nd.var, varidxs...), new_ex)
        else
            error("Don't know how to convert expression $(to_expr(nd)) to " *
                  "Einstein notation")
        end
    elseif all(dep_dims .== dep_dims[1])
        # treat as elementwise
        idxs = IDX_NAMES[1:length(dep_dims[1])]
        ivar = Expr(:ref, nd.var, idxs...)
        ideps = [Expr(:ref, dep, idxs...) for dep in dependencies(nd)]
        icall = Expr(:call, op, ideps...)
        return Expr(:(=), ivar, icall)
    else
        error("Don't know how to convert expression $(to_expr(nd)) to " *
              "Einstein notation")
    end
end

function to_einstein(g::ExGraph, nd::ExNode{:(=)})
    dep = dependencies(nd)[1]
    varidxs = g[dep].idxs[1]
    lhs = Expr(:ref, nd.var, varidxs...)
    rhs = Expr(:ref, dep, varidxs...)
    return Expr(:(=), lhs, rhs)
end



## logistic(x) = 1 ./ (1. + exp(-x))

## function main_iuye()
##     ex = :(logistic(W*x + b))
##     xs = collect(Dict(:W => rand(4, 3), :x => rand(3), :b => rand(4)))
##     xs = collect(Dict(:A => rand(4, 3), :B => rand(4, 3), :C => rand(4, 3)))
## end


# from Einstein to vectorized notation

FROM_EINSTEIN_RULES =
    OrderedDict(
                :(X[i] * I[i]) => :(sum(X)),
                :(I[i] * X[i]) => :(sum(X)),
                :(X[i,k] * Y[k,j]) => :(X * Y),
                :(X[i] * Y[i]) => :(X'Y),
                :(X[i] * Y[j]) => :(X * Y'))

function from_einstein(ex::Expr)
    g = ExGraph()
    parse!(g, ex)
    res = :(begin end)
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, from_einstein(nd))
        end
    end
    return res
end

from_einstein(nd::ExNode{:(=)}) = to_expr(nd)
from_einstein(nd::ExNode{:input}) = expr(nd)
from_einstein(nd::ExNode{:constant}) = value(nd)

function from_einstein(nd::ExNode{:call})
    ex = iexpr(nd)
    if ex.args[1]  == :*
        for (pat, rpat) in FROM_EINSTEIN_RULES
            if !isnull(matchex(pat, ex; phs=TDIFF_PHS))   # consider tryrewrite
                rex = rewrite(ex, pat, rpat; phs=TDIFF_PHS)
                return :($(nd.var) = $rex)
            end
        end
        error("No pattern to transform from Einstein notation, expression: $ex")
    else
        return to_expr(nd)
    end
end



function main_poid()
    ex = :(X[i,k] * Y[k,j] + Z[i,j])
    xs = [(:X, rand(3,2)), (:Y, rand(2,3)), (:Z, rand(3,3))]
end
