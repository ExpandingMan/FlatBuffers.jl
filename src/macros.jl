function _parsename(head)
    if @capture(head, X_{T__} <: J_)
        X
    elseif @capture(head, X_{T__})
        X
    else
        head
    end
end

function _parsefield!(fields, defaults, ex)
    # don't use splitarg here because we have to check
    if @capture(ex, x_::T_ = d_)
        push!(fields, (x, T))
        defaults[x] = d
        :($x::$T)
    elseif @capture(ex, x_::T_)
        push!(fields, (x, T))
        :($x::$T)
    elseif @capture(ex, f_ = d_)
        push!(fields, (f, :Any))
        defaults[f] = d
        f
    elseif @capture(ex, @fbunion x_)
        _parsefield!(fields, defaults, fbunion(x))
    else
        ex
    end
end

function _defaultchecks(fields, defaults)
    checks = Vector{Expr}(undef, 0)
    for (ϕ, T) ∈ fields
        dd = get(defaults, ϕ, :(FlatBuffers.default(T)))
        push!(checks, :((ϕ == $(Meta.quot(ϕ))) && return convert(T, $dd)))
    end
    checks
end

function _defaultsdef(name, fields, defaults)
    quote
        function FlatBuffers.default(::Type{<:$name}, ::Type{T}, ϕ::Symbol) where {T}
            $(_defaultchecks(fields, defaults)...)
            throw(ArgumentError("type $T has no field $ϕ"))
        end
    end
end

function _defaultconstructor(name, fields, defaults)
    defs = map(fields) do (ϕ, T)
        ϕq = Meta.quot(ϕ)
        if occursin("__utype", string(ϕ))
            ϕmain = Symbol(split(string(ϕ), "__utype")[1])
            Tmain = filter(x -> x[1] == ϕmain, fields)[1][2]
            d = get(defaults, ϕmain, :(FlatBuffers.default($Tmain)))
            ϕmainq = Meta.quot(ϕmain)
            main_arg = :(get(kwargs, $ϕmainq, $d))
            :(FlatBuffers.unionorder(fieldtype($name, $ϕmainq), typeof($main_arg))-1)
        else
            d = get(defaults, ϕ, :(FlatBuffers.default($T)))
            :(get(kwargs, $ϕq, $d))
       end
    end
    :($name(;kwargs...) = $name($(defs...)))
end

function typedec(block, btype)
    if @capture(block, struct head_; body_ end)
        mut = false
    elseif @capture(block, mutable struct head_; body_ end)
        mut = true
    else
        throw(ArgumentError("could not parse $block as a FlatBuffers struct"))
    end
    name = _parsename(head)
    fields = Vector{Tuple{Symbol,Any}}(undef, 0)
    defaults = Dict{Symbol,Any}()
    newbody = prewalk(ex -> _parsefield!(fields, defaults, ex), body)
    defs = _defaultsdef(name, fields, defaults)
    defconst = _defaultconstructor(name, fields, defaults)
    dec = if mut
        :(mutable struct $head
              $newbody
        end)
    else
        :(struct $head
              $newbody
        end)
    end
    esc(quote
        $dec
        $defs
        # TODO the below doesn't work for subtypes yet
        $defconst
        FlatBuffers.BufferType(::Type{$name}) = FlatBuffers.$btype()
    end)
end

# this method for type
macro fbunion(name, types)
    if !@capture(types, {T__})
        throw(ArgumentError("@fbunion: types must be specified in `{ … }`"))
    end
    if :Nothing ∈ T
        throw(ArgumentError("@fbunion: `Nothing` can not be specified in the flatbuffers union "*
                            "(it will be added automatically)"))
    end
    pushfirst!(T, :Nothing)
    esc(quote
        const $name = Union{$(T...)}
        for (i, T) ∈ enumerate(tuple($(T...)))
            FlatBuffers.unionorder(::Type{$name}, ::Type{T}) = i
        end
        function FlatBuffers.uniontype(::Type{$name}, i::Integer)
            for (j, T) ∈ enumerate(tuple($(T...)))
                i == j && return T
            end
            throw(ArgumentError("can't find corresponding type for $i in union $($name)"))
        end
        FlatBuffers.BufferType(::Type{$name}) = FlatBuffers.UnionType()
    end)
end

unionfieldname(x::Symbol) = Symbol(string(x,"__utype"))

function fbunion(ϕ::Union{Symbol,Expr})
    x, T, _, d = splitarg(ϕ)
    typeϕ = unionfieldname(x)
    quote
        $typeϕ::UInt8 = FlatBuffers.unionorder($T, typeof($d))-1
        $ϕ
    end
end

# this method for field
macro fbunion(ϕ); esc(fbunion(ϕ)); end

macro fbstruct(block); typedec(block, :StructType); end

macro fbtable(block); typedec(block, :TableType); end
