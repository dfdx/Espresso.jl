
# expand_deps.jl - collect & expand all dependencies of a variable in  AbstractExGraph

## collect_deps

function collect_deps!(g::AbstractExGraph, nd::ExNode, depth::Int, result::Set{Symbol})
    if depth > 0
        for dep in dependencies(nd)
            if haskey(g, dep)
                collect_deps!(g, g[dep], depth - 1, result)
            end
        end
    end
    push!(result, varname(nd))
end


function collect_deps!(g::AbstractExGraph, ex::Expr, depth::Int, result::Set{Symbol})
    vnames = get_var_names(ex, rec=true)
    for vname in vnames
        collect_deps!(g, vname, depth, result)
    end
end


function collect_deps!(g::AbstractExGraph, x::Symbol, depth::Int, result::Set{Symbol})
    if haskey(g, x)
        collect_deps!(g, g[x], depth, result)
    end
end


function collect_deps!(g::AbstractExGraph, x, depth::Int, result::Set{Symbol})
    # do nothing
end


function collect_deps(g::AbstractExGraph, nd::ExNode, depth::Int=typemax(Int))
    result = Set{Symbol}()
    collect_deps!(g, nd, depth, result)
    return result
end


function collect_deps(g::AbstractExGraph, ex::Expr, depth::Int=typemax(Int))
    result = Set{Symbol}()
    collect_deps!(g, ex, depth, result)
    return result
end


function collect_deps(g::AbstractExGraph, x::Symbol, depth::Int=typemax(Int))
    result = Set{Symbol}()
    collect_deps!(g, x, depth, result)
    return result
end


function collect_deps(g::AbstractExGraph, xs::Vector{Symbol}, depth::Int=typemax(Int))
    result = Set{Symbol}()
    for x in xs
        collect_deps!(g, x, depth, result)
    end
    return result
end


collect_deps(g::AbstractExGraph, x, depth::Int=typemax(Int)) = Set{Symbol}()



## expand_deps


function expand_deps!(g::AbstractExGraph, nd::ExNode{:input}, depth::Int, result::Vector{Expr})
    # do nothing
end

function expand_deps!(g::AbstractExGraph, nd::ExNode{:constat}, depth::Int, result::Vector{Expr})
    push!(result, to_expr(nd))
end

function expand_deps!(g::AbstractExGraph, nd::ExNode{:(=)}, depth::Int, result::Vector{Expr})
    if depth > 0
        expand_deps!(g, [g[var] for var in dependencies(nd)], depth - 1, result)
        push!(result, to_expr(nd))
    end
end

function expand_deps!(g::AbstractExGraph, nd::ExNode{:call}, depth::Int, result::Vector{Expr})
    if depth > 0
        for dep in dependencies(nd)
            expand_deps!(g, g[end], depth - 1, result)
        end
        push!(result, to_expr(nd))
    end
end

function expand_deps(g::AbstractExGraph, nd::ExNode, depth::Int=typemax(Int))
    deps = collect_deps(g, nd, depth)
    ex = Expr(:block)
    for nd in g.tape
        if !isa(nd, ExNode{:input}) && in(varname(nd), deps)
            push!(ex.args, to_expr(nd))
        end
    end
    return ex
end
