
# expand_deps.jl - collect & expand all dependencies of a variable in  ExGraph

function expand_deps!(g::ExGraph, nd::ExNode{:input}, depth::Int, result::Vector{Expr})
    # do nothing
end

function expand_deps!(g::ExGraph, nd::ExNode{:constat}, depth::Int, result::Vector{Expr})
    push!(result, to_expr(nd))
end

function expand_deps!(g::ExGraph, nd::ExNode{:(=)}, depth::Int, result::Vector{Expr})
    if depth > 0
        expand_deps!(g, [g[var] for var in dependencies(nd)], depth - 1, result)
        push!(result, to_expr(nd))
    end
end

function expand_deps!(g::ExGraph, nd::ExNode{:call}, depth::Int, result::Vector{Expr})
    if depth > 0
        for dep in dependencies(nd)
            expand_deps!(g, g[end], depth - 1, result)
        end
        push!(result, to_expr(nd))
    end
end


function collect_deps!(result::Set{Symbol}, g::ExGraph, nd::ExNode, depth::Int=typemax(Int))
    if depth > 0
        for dep in dependencies(nd)
            if haskey(g, dep)
                collect_deps!(result, g, g[dep], depth - 1)
            end
        end
    end
    push!(result, varname(nd))
end


function collect_deps!(result::Set{Symbol}, g::ExGraph, ex::Expr, depth::Int=typemax(Int))
    if ex.head == :call
        for arg in ex.args[2:end]
            collect_deps!(result, g, arg, depth)
        end
    elseif ex.head == :ref
        collect_deps!(result, g, ex.args[1], depth)
    end
end


function collect_deps!(result::Set{Symbol}, g::ExGraph, x, depth::Int=typemax(Int))
    # do nothing
end


function collect_deps(g::ExGraph, nd::ExNode, depth::Int=typemax(Int))
    result = Set{Symbol}()
    collect_deps!(result, g, nd, depth)
    return result
end


function collect_deps(g::ExGraph, ex::Expr, depth::Int=typemax(Int))
    result = Set{Symbol}()
    collect_deps!(result, g, ex, depth)
    return result
end


collect_deps(g::ExGraph, x, depth::Int=typemax(Int)) = Set{Symbol}()



function expand_deps(g::ExGraph, nd::ExNode, depth::Int=typemax(Int))
    deps = collect_deps(g, nd, depth)
    ex = Expr(:block)
    for nd in g.tape
        if !isa(nd, ExNode{:input}) && in(varname(nd), deps)
            push!(ex.args, to_expr(nd))
        end
    end
    return ex
end
