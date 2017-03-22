
# propagate_size.jl - propagate size of variables in ExGraph, saving them into g.ctx[:sizes]

const SIZE_PROP_RULES =
    Dict((:*, [0, 0]) => :(()),
         (:*, [2, 1]) => :((_1[1])),
         (:*, [2, 2]) => :((_1[1], _2[2])),
         (:.*, [1, 1]) => :((_1, _2)))

function propagate_size!(g::ExGraph, nd::ExNode{:input})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    sizes[varname(nd)] = :(size($(varname(nd))))
end

function propagate_size!(g::ExGraph, nd::ExNode{:constant})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    sz = size(value(nd))
    sizes[varname(nd)] = Expr(:tuple, sz...)
end

# function indexperm(lhs_idxs::Vector, rhs_idxs::Vector)
#     perm = Int[]
#     for lhs_idx in lhs_idxs
#         rhs_pos = findfirst(rhs_idxs, lhs_idx)
#         if rhs_pos < 1
#             error("LHS index $lhs_idx doesn't happen on RHS")
#         end
#         push!(perm, rhs_pos)
#     end
#     return perm
# end

function propagated_size(g::ExGraph, nd::ExNode{:(=)})
    sizes = @get_or_create(g.ctx, :sizes, Dict()) 
    dep = dependencies(nd)[1]    
    idxs = get_indices(to_expr(nd))
    if length(idxs) == 0 || (length(idxs) == 2 && idxs[1] == idxs[2])
        # not indexed or indices on LHS and RHS are equal
        return sizes[dep]
    elseif isempty(varidxs(nd))
        # special case for scalars (produce nicer expression then the following)
        return Expr(:tuple)
    else
        # perm = indexperm(varidxs(nd), get_indices(expr(nd))[1])
        perm = findperm(idxs[1], idxs[2])
        dep_sz = sizes[dep]
        var_sz_maybe = tryrewrite(dep_sz, :(size(_V)), :(size(_V, $(perm...))))
        if !isnull(var_sz_maybe)
            return get(var_sz_maybe)
        elseif length(perm) == 1
            # special case - only one index
            return simplify(:($(dep_sz)[$(perm[1])]))
        else
            return simplify(:($(dep_sz)[[$(perm...)]]))
        end
    end
end

function propagate_size!(g::ExGraph, nd::ExNode{:(=)})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    sizes[varname(nd)] = propagated_size(g, nd)
end


function graph_inputs(g::ExGraph)
    res = Dict()
    for nd in g.tape
        if isa(nd, ExNode{:input})
            res[varname(nd)] = value(nd)
        end
    end
    return res
end

function ndims_from_size(g::ExGraph, var::Symbol)
    inputs = graph_inputs(g)
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    evex = subs(sizes[var], inputs)
    sz = eval(evex)
    return length(sz)
end

function propagate_size!(g::ExGraph, nd::ExNode{:call})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    deps = dependencies(nd)
    if in(:I, deps)
        lhs_idxs = varidxs(nd)
        I_pos = findfirst(deps, :I)
        not_I_pos = 3 - I_pos
        idxs = get_indices(to_expr(nd))
        not_I_idxs = idxs[not_I_pos + 1]
        idxs_to_keep = findin(lhs_idxs, not_I_idxs)
        if isempty(idxs_to_keep)
            sizes[varname(nd)] = :(())
        else
            dep_size_expr = sizes[deps[not_I_pos]]
            size_expr = simplify(Expr(:ref, dep_size_expr, idxs_to_keep...))
            sizes[varname(nd)] = size_expr
        end
    elseif all(dep -> haskey(g, dep), deps)
        dep_dims = [ndims_from_size(g, dep) for dep in deps]
        sz_key = (expr(nd).args[1], dep_dims)
        if haskey(SIZE_PROP_RULES, sz_key)
            rpat = SIZE_PROP_RULES[sz_key]
            dep_sizes = [sizes[dep] for dep in deps]
            size_names = [Symbol("_$i") for i=1:length(deps)]
            st = Dict(zip(size_names, dep_sizes))
            size_ex = simplify(subs(rpat, st))
            sizes[varname(nd)] = size_ex
        else
            i = findmax(dep_dims)[2]
            size_ex = sizes[deps[i]]
            sizes[varname(nd)] = size_ex
        end
    else
        error("Can't propagate size of $nd: not all deps present in graph")
    end
end


function propagate_size!(g::ExGraph, nd::ExNode{:bcast})
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    haskey(sizes, varname(nd)) && return
    deps = dependencies(nd)
    dep_dims = [ndims_from_size(g, dep) for dep in deps]
    i = findmax(dep_dims)[2]
    size_ex = sizes[deps[i]]
    sizes[varname(nd)] = size_ex
end


function propagate_size!(g::ExGraph)
    for nd in g.tape
        propagate_size!(g, nd)
    end
end



# special case - sizes of derivatives

function propagate_deriv_size!(g::ExGraph, dd_name::Symbol)
    sizes = @get_or_create(g.ctx, :sizes, Dict())
    rg = match(r"(d.+)_(d.+)", String(dd_name))
    @assert length(rg.captures) == 2
    str_dnames = rg.captures
    zname = Symbol(str_dnames[1][2:end])
    xname = Symbol(split(str_dnames[2][2:end], "__")[1]) # cut down `__$(i)` part if any    
    zsize, xsize = (sizes[zname], sizes[xname])
    if zsize == :(())
        # output var is constant
        sizes[dd_name] = xsize
    else
        sizes[dd_name] = :(($zsize..., $xsize...)) |> simplify
    end
end


function propagate_deriv_size!(g::ExGraph)
    for nd in g.tape
        vname = varname(nd)
        if match(r"(d.+)_(d.+)", String(vname)) != nothing
            propagate_deriv_size!(g, vname)
        end
    end
end



