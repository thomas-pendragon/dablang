class RemoveUnreachable
  def run(node)
    flat = node.blocks[0]

    flat.each do |block|
      remove = []
      skip = false
      block.each do |instr|
        remove << instr if skip
        skip ||= instr.is_a?(DabNodeBaseJump)
        skip ||= instr.is_a?(DabNodeReturn)
      end

      remove.each(&:remove!)
    end

    # TODO: status
  end
end
