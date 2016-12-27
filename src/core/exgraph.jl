
# exgraph.jl - expression graph as a list of primitive expression nodes

# exnode

@runonce type ExNode{C}         # C - category of node, e.g. :call, :=, etc.
    var::Symbol                 # variable name
    ex::Any                     # simple expression that produces name
    idxs::Vector{Vector}        # indexes (var : args) if in Einstein notation
    val::Any                    # example value
end

ExNode(C::Symbol, var::Symbol, ex::Any) = ExNode{C}(var, ex, [], nothing)

# category{C}(nd::ExNode{C}) = C
variable(nd::ExNode) = nd.var
value(nd::ExNode) = nd.val
expr(nd::ExNode) = nd.ex
function iexpr(nd::ExNode)
    varex = Expr(:ref, nd.var, nd.idxs[1]...)
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    return depex
end


## deps

"""Get symbols of dependenices of this node"""
dependencies(nd::ExNode{:input}) = Symbol[]
dependencies(nd::ExNode{:constant}) = Symbol[]
dependencies(nd::ExNode{:(=)}) = [nd.ex]
dependencies(nd::ExNode{:call}) = nd.ex.args[2:end]

to_expr(nd::ExNode) = :($(nd.var) = $(nd.ex))
function to_einsum_expr(nd::ExNode)
    varidxs = nd.idxs[1]
    varex = length(varidxs) > 0 ? Expr(:ref, nd.var, varidxs...) : nd.var
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    ex_without_I = without(nd.ex, :I)
    depex = add_indices(ex_without_I, s2i)
    assign_ex = Expr(:(:=), varex, depex)
    return Expr(:macrocall, Symbol("@einsum"), assign_ex)
end

to_iexpr(nd::ExNode{:constant}) = to_expr(nd)

function to_iexpr(nd::ExNode)
    varex = maybe_indexed(nd.var, nd.idxs[1])
    s2i = Dict([(dep, idxs)
                for (dep, idxs) in zip(dependencies(nd), nd.idxs[2:end])])
    depex = add_indices(nd.ex, s2i)
    return Expr(:(=), varex, depex)
end

function Base.show{C}(io::IO, nd::ExNode{C})
    val = isa(nd.val, AbstractArray) ? "<$(typeof(nd.val))>" : nd.val
    print(io, "ExNode{$C}($(to_expr(nd)) | $val)")
end

isindexed(nd::ExNode) = !isempty(nd.idxs) && any(x -> !isempty(x), nd.idxs)


# exgraph

@runonce type ExGraph
    ex::Expr                       # original expression used to build ExGraph
    tape::Vector{ExNode}           # list of ExNode-s
    idx::Dict{Symbol, ExNode}      # map from var name to its node in the graph
    ctx::Dict{Any,Any}             # settings and caches
end

function ExGraph(ex::Expr; ctx=Dict(), inputs...)
    ctx = to_context(ctx)
    @get_or_create(ctx, :mod, current_module())
    g = ExGraph(ex, ExNode[], Dict(), ctx)
    for (var, val) in inputs
        addnode!(g, :input, var, var; val=val)
    end
    # for (var, val) in get(ctx, :constants, [])
    #     addnode!(g, :constant, var, var; val=val)
    # end
    parse!(g, ex)
    collapse_assignments!(g)
    return g
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
Base.getindex(g::ExGraph, i::Integer) = g.tape[i]
Base.endof(g::ExGraph) = endof(g.tape)

function to_iexpr(g::ExGraph)
    res = quote end
    for nd in g.tape
        if !isa(nd, ExNode{:input})
            push!(res.args, to_iexpr(nd))
        end
    end
    return res
end


"""Extract symbols that may make conflicts with temporary names in ExGraph"""
function possible_temp_names(ex::Expr)
    names = unique(flatten(map(possible_temp_names, ex.args)))
    return convert(Vector{Symbol}, names)
end

possible_temp_names(name::Symbol) = (startswith(string(name), "tmp") ?
                                     [name] :
                                     Symbol[])
possible_temp_names(x) = Symbol[]


"""Generate new unique name for intermediate variable in graph"""
function genname(g::ExGraph)
    last_id = @get_or_create(g.ctx, :last_id, 1)
    possible_names = @get_or_create(g.ctx, :possible_names,
                                    possible_temp_names(g.ex))
    name = Symbol("tmp$(last_id)")
    while in(name, possible_names)
        last_id += 1
        name = Symbol("tmp$(last_id)")
    end
    g.ctx[:last_id] = last_id + 1
    return name
end


## addnode!

"""
Add new node to a graph. Expression should be simple, e.g.
nested calls or blocks are not allowed (use parse!() for it).
"""
function addnode!(g::ExGraph, C::Symbol, var::Symbol, ex::Any;
                  idxs=Vector[], val=nothing)
    nd = ExNode{C}(var, ex, idxs, val)
    push!(g.tape, nd)
    g.idx[var] = nd
    return var
end


## parse!

"""
Parse Julia expression and build ExGraph in-place.
Return the name of the output variable.
"""
parse!(g::ExGraph, ex::Expr) = parse!(g, to_exh(ex))
parse!(g::ExGraph, ::LineNumberNode) = (:nil, Symbol[])
parse!(g::ExGraph, ::ExH{:line}) = (:nil, Symbol[])
parse!(g::ExGraph, s::Symbol) = (s, Symbol[])
parse!(g::ExGraph, gr::GlobalRef) = (gr, Symbol[])

function parse!(g::ExGraph, x::Number)
    var = addnode!(g, :constant, genname(g), x; val=x)
    return var, Symbol[]
end

function parse!(g::ExGraph, x::AbstractArray)
    name = addnode!(g, :constant, genname(g), x; val=x)
    return name, Symbol[]
end

split_indexed(name::Symbol) = (name, Symbol[])
split_indexed(ex::Expr) = (ex.args[1], convert(Vector{Symbol}, ex.args[2:end]))

function parse!(g::ExGraph, ex::ExH{:(=)})
    lhs, rhs = ex.args
    var, varidxs = split_indexed(lhs)
    dep, depidxs = parse!(g, rhs)
    idxs = Vector{Symbol}[varidxs, depidxs]
    addnode!(g, :(=), var, dep; idxs=idxs)
    return var, varidxs
end


function parse!(g::ExGraph, ex::ExH{:ref})
    return ex.args[1], convert(Vector{Symbol}, ex.args[2:end])
end


function parse!(g::ExGraph, ex::ExH{:call})   
    op = canonical(g.ctx[:mod], ex.args[1])
    deps, depidxs = unzip([parse!(g, arg) for arg in ex.args[2:end]])
    pex = Expr(:call, op, deps...)
    varidxs = forall_indices(op, depidxs)
    idxs = insert!(copy(depidxs), 1, varidxs)
    var = addnode!(g, :call, genname(g), pex; idxs=idxs)
    return var, varidxs
end

function parse!(g::ExGraph, ex::ExH{:block})
    name_idxs = [parse!(g, arg) for arg in ex.args]
    return name_idxs[end]
end

function parse!(g::ExGraph, ex::ExH{:body})
    name_idxs = [parse!(g, arg) for arg in ex.args]
    return name_idxs[end]
end


## evaluate!

"""
Evaluate node, i.e. fill its `val` by evaluating node's expression using
values of its dependencies.
"""
evaluate!(g::ExGraph, node::ExNode{:constant}) = node.val
evaluate!(g::ExGraph, node::ExNode{:input}) = node.val


function mk_eval_expr(g::ExGraph, nd::ExNode)
    dep_nodes = [g.idx[dep] for dep in dependencies(nd) if haskey(g, dep)]
    deps_vals = [(nd.var, nd.val) for nd in dep_nodes]
    block = Expr(:block)
    for (dep, val) in deps_vals
        push!(block.args, Expr(:(=), dep, val))
    end
    push!(block.args, isindexed(nd) ? to_einsum_expr(nd) : to_expr(nd))
    push!(block.args, nd.var)
    return block
end


function evaluate!(g::ExGraph, nd::ExNode{:(=)})
    if (nd.val != nothing) return nd.val end
    dep = dependencies(nd)[1]
    evaluate!(g, g.idx[dep])
    evex = mk_eval_expr(g, nd)
    nd.val = eval(evex)
    return nd.val
end

function evaluate!(g::ExGraph, nd::ExNode{:call})
    if (nd.val != nothing) return nd.val end
    deps = dependencies(nd)
    for dep in deps
        # if dep is not in graph, consider it a global constant (like π)
        if haskey(g.idx, dep)
            evaluate!(g, g[dep])
        end
    end
    evex = mk_eval_expr(g, nd)
    nd.val = eval(evex)
    return nd.val
end

evaluate!(g::ExGraph, name::Symbol) = evaluate!(g, g.idx[name])
evaluate!(g::ExGraph) = evaluate!(g, g[end])


## graph simlification

istemp(var::Symbol) = startswith(string(var), "tmp")


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
        nd.ex = subs(nd.ex, st)
        if isa(nd, ExNode{:(=)}) &&
            (length(nd.idxs) == 0 || nd.idxs[1] == nd.idxs[2])
            dep = dependencies(nd)[1]
            # st[dep] = nd.var
            if istemp(dep) # && !istemp(nd.var)
                st[dep] = nd.var
            else
                st[nd.var] = dep
            end
            push!(delvars, nd.var)
        end
    end
    new_tape = Vector{ExNode}()
    new_idx = Dict{Symbol, ExNode}()
    for nd in g.tape
        if !in(nd.var, delvars)
            if haskey(st, nd.var)
                new_nd = deepcopy(nd)
                new_nd.var = st[nd.var]
                new_nd.ex = subs(nd.ex, st)
                push!(new_tape, new_nd)
                new_idx[new_nd.var] = new_nd
            else
                push!(new_tape, nd)
                new_idx[nd.var] = nd
            end
        end
    end
    g.tape = new_tape
    g.idx = new_idx
end

