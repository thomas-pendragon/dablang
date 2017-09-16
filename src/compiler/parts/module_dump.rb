module DabNodeModuleDump
  def inspect
    to_s
  end

  def to_s(show_ids = true)
    tt = self.my_type&.type_string
    tt = "#{tt}!".bold if self.my_type&.concrete?
    tt = sprintf('(%s)', tt).white
    src = sprintf('%s:%d', self.source_file || '?', self.source_line || -1)
    flags = ''
    exdump = extra_dump.to_s
    exdump = ' ' + exdump.bold unless exdump.empty?
    pinfo = ''
    if parent
      children_info = parent.children_info
      parent_info = children_info[self]
    end
    if parent_info
      pinfo = "#{parent_info}: ".bold
    end
    if show_ids
      pinfo = self.object_id.to_s.bold.blue + ': ' + pinfo
    end
    deadflag = deleted? ? ' [DEAD]'.bold : ''
    sprintf('%s%s%s%s %s %s%s', pinfo, self.class.name, exdump, flags, tt, src.white, deadflag)
  end

  def dump(show_ids = false, level = 0, background_colors = {}, skip_output: false)
    text = sprintf('%s - %s', '  ' * level, to_s(show_ids))
    text = text.green if constant?
    if has_errors?
      text = if @self_errors.count > 0
               text.light_red.bold + " (#{@self_errors.map(&:message).join(', ')})"
             else
               text.light_red
             end
    end
    background_colors.each do |color_key, array|
      if array.include?(self)
        text = text.colorize(background: color_key)
        break
      end
    end
    err(text) unless skip_output
    @children.each do |child|
      if child.nil?
        err('%s ~ [nil]', '  ' * (level + 1))
      elsif child.is_a? DabNode
        if child.parent != self
          raise "child #{child} is broken, parent is '#{child.parent}', should be '#{self}'"
        end
        child.dump(show_ids, level + 1, background_colors, skip_output: skip_output)
      else
        err('%s ~ %s', '  ' * (level + 1), child.to_s) unless skip_output
      end
    end
  end
end
