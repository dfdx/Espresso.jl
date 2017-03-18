
# exgraph.jl - expression graph as a list of primitive expression nodes


@runonce type ExGraph
    tape::Vector{ExNode}           # list of ExNode-s
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    ctx::Dict{Any,Any}             # settings and caches
end

function ExGraph(; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    @get_or_create(ctx, :mod, current_module())
    g = ExGraph(ExNode[], Dict(), ctx)
    for (var, val) in inputs
        addnode!(g, :input, var, var; val=val)
    end
    return g
end

function ExGraph(ex::Expr; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    g = ExGraph(;ctx=ctx, inputs...)
    g.ctx[:expr] = ex
    parse!(g, ex)
    collapse_assignments!(g)
    return g
end


function Base.deepcopy(g::ExGraph)
    ctx_copy = to_context(Dict())
    for (k, v) in g.ctx
        if isa(v, Module)
            ctx_copy[k] = v
        else
            ctx_copy[k] = deepcopy(v)
        end
    end
    return ExGraph(deepcopy(g.tape), deepcopy(g.idx), ctx_copy)
end


function Base.show(io::IO, g::ExGraph)
    print(io, "ExGraph\n")
    for node in g.tape
        print(io, "  $node\n")
    end
end

Base.haskey(g::ExGraph, var::Symbol) = haskey(g.idx, var)
Base.get(g::ExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::ExGraph, var::Symbol) = g.idx[var]
Base.getindex(g::ExGraph, var::String) = g.idx[Symbol(var)]
Base.getindex(g::ExGraph, i::Integer) = g.tape[i]
Base.endof(g::ExGraph) = endof(g.tape)

function to_expr(g::ExGraph)
    res = quote end
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, to_expr(nd))
        end
    end
    return res
end


# """Extract symbols that may make conflicts with temporary names in ExGraph"""
# function possible_temp_names(ex::Expr)
#     names = unique(flatten(map(possible_temp_names, ex.args)))
#     return convert(Vector{Symbol}, names)
# end

# possible_temp_names(name::Symbol) = (startswith(string(name), "tmp") ?
#                                      [name] :
#                                      Symbol[])
# possible_temp_names(x) = Symbol[]


"""Generate a new unique name for intermediate variable in graph"""
function genname()
    return gensym()
end

# for compatibility, will be removed somewhere in the future
# function genname(g::ExGraph)
#     return gensym()
# end

function gennames(count::Int)
    return [gensym() for _=1:count]
end

## addnode!

"""
Add a new node to a graph. Expression should be simple, e.g.
nested calls or blocks are not allowed (use parse!() for it).
"""
function addnode!(g::ExGraph, nd::ExNode)
    push!(g.tape, nd)
    g.idx[varname(nd)] = nd
    return varname(nd)
end

function addnode!(g::ExGraph, C::Symbol, var::Union{Symbol,Expr}, ex::Any; val=nothing)
    nd = ExNode{C}(var, ex; val=val)
    addnode!(g, nd)
    return var
end



## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, ExH(ex))
parse!(g::ExGraph, ::LineNumberNode) = :nil
parse!(g::ExGraph, ::ExH{:line}) = :nil
parse!(g::ExGraph, s::Symbol) = s
# parse!(g::ExGraph, gr::GlobalRef) = (gr, [])

function parse!(g::ExGraph, x::Number)
    var = addnode!(g, :constant, genname(), x; val=x)
    return var
end


function parse!(g::ExGraph, x::AbstractArray)
    var = addnode!(g, :constant, genname(), x; val=x)
    return var
end


function parse!(g::ExGraph, ex::ExH{:(=)})
    var, rhs = ex.args
    vname = split_indexed(var)[1]
    dep = parse!(g, rhs)
    addnode!(g, :(=), var, dep)
    return vname
end


function parse!(g::ExGraph, ex::ExH{:ref})
    return Expr(ex)
end


function parse!(g::ExGraph, ex::ExH{:call})
    op = canonical(g.ctx[:mod], ex.args[1])
    deps = [parse!(g, arg) for arg in ex.args[2:end]]
    depnames, depidxs = unzip(map(split_indexed, deps))
    pex = Expr(:call, op, deps...)
    vidxs = forall_indices(op, [split_indexed(dep)[2] for dep in deps])
    var = addnode!(g, :call, make_indexed(genname(), vidxs), pex)
    return var
end


function parse!(g::ExGraph, ex::ExH{:.})
    @assert(isa(ex.args[2], Expr) && ex.args[2].head == :tuple,
            "Dot (.) is only allowedd in broadcasting (e.g. `f.(x)`), but `$ex` passed in")
    op = canonical(g.ctx[:mod], ex.args[1])
    deps = [parse!(g, arg) for arg in ex.args[2].args]
    # pex = Expr(:call, op, deps...)
    pex = Expr(:., op, Expr(:tuple, deps...))
    vidxs = forall_indices(op, [split_indexed(dep)[2] for dep in deps])
    var = addnode!(g, :bcast, make_indexed(genname(), vidxs), pex)
    return var
end


function parse!(g::ExGraph, ex::ExH{Symbol("'")})
    dep = parse!(g, ex.args[1])
    depname, depidxs = split_indexed(dep)
    @assert isempty(depidxs) ":' is not allowed in Einstin notation"
    pex = :(transpose($dep))    
    var = addnode!(g, :call, genname(), pex)
    return var
end

function parse!(g::ExGraph, ex::Union{ExH{:block}, ExH{:body}})
    deps = [parse!(g, arg) for arg in ex.args]
    return deps[end]
end


## evaluate!

"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
evaluate!(g::ExGraph, nd::ExNode{:constant}) = value(nd)
evaluate!(g::ExGraph, nd::ExNode{:input}) = value(nd)


function mk_eval_expr(g::ExGraph, nd::ExNode)
    dep_nodes = [g[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = [(varname(nd), value(nd)) for nd in dep_nodes]
    eval_ex = Expr(:block, Expr(:let, Expr(:block)))
    block = eval_ex.args[1].args[1]
    for (dep, val) in deps_vals
        push!(block.args, :(local $dep = $val))
    end
    push!(block.args, isindexed(nd) ? to_einsum_expr(nd) : to_expr(nd))
    push!(block.args, varname(nd))
    return eval_ex
end


function evaluate!(g::ExGraph, nd::ExNode{:(=)})
    if (value(nd) != nothing) return value(nd) end
    dep = dependencies(nd)[1]
    evaluate!(g, g[dep])
    evex = mk_eval_expr(g, nd)
    value!(nd, eval(evex))
    return value(nd)
end

function evaluate!(g::ExGraph, nd::ExNode{:call})
    if (value(nd) != nothing) return value(nd) end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep])
        end
    end
    evex = mk_eval_expr(g, nd)
    value!(nd, eval(evex))
    return value(nd)
end


function evaluate!(g::ExGraph, nd::ExNode{:bcast})
    if (value(nd) != nothing) return value(nd) end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep])
        end
    end
    evex = mk_eval_expr(g, nd)
    value!(nd, eval(evex))
    return value(nd)
end



evaluate!(g::ExGraph, name::Symbol) = evaluate!(g, g[name])
evaluate!(g::ExGraph) = evaluate!(g, g[end])


## graph simlification

istemp(var::Symbol) = startswith(string(var), "##")


"""
Collapse unnecessary assignment nodes, rewriting all affected nodes. Example:

    tmp1 = x * y
    z = tmp1

will be rewritten to

    z = x * y
"""
function collapse_assignments!(g::ExGraph)
    st = Dict{Symbol, Symbol}()
    delvars = Set{Symbol}()
    for nd in g.tape
        expr!(nd, subs(expr(nd), st))
        vidxs = varidxs(nd)
        depidxs = get_indices(expr(nd))
        if isa(nd, ExNode{:(=)}) && !isempty(depidxs) && vidxs == depidxs[1]
            vname = varname(nd)
            dep = dependencies(nd)[1]            
            if istemp(dep)
                # if dependency is a temp var name, replace it with the normal one
                st[dep] = vname
            else
                # otherwise replace all future alias occurrences with the original one
                st[vname] = dep
            end
            push!(delvars, vname)
        end
    end
    new_tape = Vector{ExNode}()
    new_idx = Dict{Symbol, ExNode}()
    for nd in g.tape
        vname = varname(nd)
        if !in(vname, delvars)
            if haskey(st, vname)
                new_nd = deepcopy(nd)
                # new_nd.var = st[nd.var]
                variable!(new_nd, subs(variable(nd), st))
                # new_nd.ex = subs(nd.ex, st)
                expr!(new_nd, subs(expr(nd), st))                
                push!(new_tape, new_nd)
                new_idx[varname(new_nd)] = new_nd
            else
                push!(new_tape, nd)
                new_idx[varname(nd)] = nd
            end
        end
    end
    g.tape = new_tape
    g.idx = new_idx
end


