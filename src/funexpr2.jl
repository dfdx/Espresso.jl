
# funexpr.jl - extract arguments and (sanitized) expression of a function body.
#
# Here sanitization means removing things like LineNumberNode and replacing
# hard-to-consume nodes (e.g. `GloabalRef` and `return`) with their simple
# counterparts (e.g. expression with `.` and variable node).

sanitize(x) = x
sanitize(ex::Expr) = sanitize(to_exh(ex))
sanitize(ex::LineNumberNode) = nothing
sanitize(ex::ExH{:line}) = nothing
sanitize(ex::ExH{:return}) = ex.args[1]

function sanitize(ex::ExH{:block})
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return length(new_args) == 1 ? new_args[1] : Expr(ex.head, new_args...)
end

function sanitize{H}(ex::ExH{H})
    sanitized_args = [sanitize(arg) for arg in ex.args]
    new_args = filter(arg -> arg != nothing, sanitized_args)
    return Expr(H, new_args...)
end

function sanitize(ref::GlobalRef)
    # mod = Main # module doesn't actually matter since GlobalRef contains it anyway
    # return canonical(mod, ref)
    return Expr(:., ref.mod, QuoteNode(ref.name))
end


function is_doc_macro(ref::GlobalRef)
    return ref.mod == Core && ref.name == Symbol("@doc")
end

is_doc_macro(ex::Expr) = ex == :(Core.@doc)
is_doc_macro(x) = false


function funtypes(ex::Union{ExH{:function}, ExH{:(=)}, Expr})
    args = ex.args[1].args[2:end]
    return tuple([isa(arg, Symbol) ? Any : eval(arg.args[2]) for arg in  args]...)
end


findfun(x, name) = Nullable{Expr}()

function findfun(ex::Expr, name::Symbol, types::Tuple{DataType})::Nullable{Expr}
    return findfun(ExH(ex), name)
end

function findfun(ex::ExH{:function}, name::Symbol, types::Tuple{DataType})
    if ex.args[1].args[1] == name && types == funtypes(ex)
        return Nullable(ex)
    else
        return Nullable{Expr}()
    end
end

function findfun{N}(ex::ExH{:(=)}, name::Symbol, types::NTuple{N,DataType})
    if ex.args[1].head == :call && ex.args[1].args[1] == name && types == funtypes(ex)
        return Nullable(ex)
    else
        return Nullable{Expr}()
    end
end

function findfun{N}(ex::ExH{:macrocall}, name::Symbol, types::NTuple{N,DataType})
    if is_doc_macro(ex.args[1])
        return findfun(ex.args[3], name, types)
    else
        return Nullable{Expr}()
    end
end

function findfun{N}(ex::ExH{:module}, name::Symbol, types::NTuple{N,DataType})
    for subex in ex.args[3].args
        nullex = findfun(subex, name, types)
        if !isnull(nullex)
            return nullex
        end
    end
    return Nullable{Expr}()
end


function funexpr(f::Function, types::Tuple{DataType})
    method = Sugar.get_method(f, types)
    # realtypes = tuple(method.sig.parameters[2:end]...)
    method_file = string(method.file)
    linestart = method.line
    file = Sugar.get_source_file(method_file, linestart)
    open(file) do io
        while !eof(io)
            ex = parse(io)
            nullfun = findfun(ex, method.name, types)
            if !isnull(nullfun)
                println(get(nullfun))
            end
        end
    end
end





# method.source.slotnames
