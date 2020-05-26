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

function typedec(block)
    if !(@capture(block, struct head_; body_ end) || @capture(block, mutable struct head_; body_ end))
        throw(ArgumentError("could not parse $block as a FlatBuffers struct"))
    end
    name = _parsename(head)
    fields = Vector{Tuple{Symbol,Any}}(undef, 0)
    defaults = Dict{Symbol,Any}()
    newbody = prewalk(ex -> _parsefield!(fields, defaults, ex), body)
    defs = _defaultsdef(name, fields, defaults)
    esc(quote
        struct $head
            $newbody
        end
        $defs
        # TODO the below doesn't work for subtypes yet
        # TODO also want more constructors
        $name() = $name((FlatBuffers.default($name, i) for i ∈ 1:length(fieldtypes($name)))...)
    end)
end


macro fbstruct(block)
    typedec(block)
end

macro fbtable(block)
    typedec(block)
end
