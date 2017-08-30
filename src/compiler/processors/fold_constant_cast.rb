class FoldConstantCast
  def run(cast)
    value = cast.value
    return unless value.constant?

    target_type = cast.target_type

    cast.replace_with!(value.cast_to(target_type))
  end
end
