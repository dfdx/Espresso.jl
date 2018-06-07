## sugar.jl - (hopefully) temporary copy of needed parts of Sugar.jl package

# jlhome() = ccall(:jl_get_julia_home, Any, ())
jlhome() = Sys.BINDIR

function juliabasepath(file)
    srcdir = joinpath(jlhome(),"..","..","base")
    releasedir = joinpath(jlhome(),"..","share","julia","base")
    normpath(joinpath(isdir(srcdir) ? srcdir : releasedir, file))
end

function get_source_file(path::AbstractString, ln)
    isfile(path) && return path
    # if not a file, it might be in julia base
    file = juliabasepath(path)
    if !isfile(file)
        throw(LoadError(path, Int(ln), ErrorException("file $path not found")))
    end
    file
end

function get_method(f, types::Type)
    get_method(f, (types.parameters...,))
end
function get_method(ftype::DataType, types::Tuple)
    world = typemax(UInt)
    if !isclosure(ftype)
        ftype = Type{ftype}
    end
    tt = Tuple{ftype, to_tuple(types)...}
    (ti, env, meth) = Base._methods_by_ftype(tt, 1, world)[1]
    Base.func_for_method_checked(meth, tt)
end
function get_method(f, types::Tuple)
    if !all(isconcretetype, types)
        error("Not all types are concrete: $types")
    end
    # make sure there is a specialization with precompile
    # TODO, figure out a better way, since this method is not very reliable.
    # (I think, e.g. anonymous functions don't work)
    precompile(f, (types...,))
    x = methods(f, types)
    if isempty(x)
        throw(NoMethodError(f, types))
    elseif length(x) != 1
        error("
            More than one method found for signature $f $types.
            Please use more specific types!
        ")
    end
    first(x)
end



"""
Looks up the source of `method` in the file path found in `method`.
Returns the AST and source string, might throw an LoadError if file not found.
"""
function get_source_at(file, linestart)
    file = get_source_file(file, linestart)
    code, str = open(file) do io
        line = ""
        for i=1:linestart-1
            line = readline(io)
        end
        try # lines can be one off, which will result in a parse error
            Meta.parse(line)
        catch e
            line = readline(io)
        end
        while !eof(io)
            line = line * "\n" * readline(io)
            e = Base.parse_input_line(line; filename=file)
            if !(isa(e,Expr) && e.head === :incomplete)
                return e, line
            end
        end
    end
    code, str
end
