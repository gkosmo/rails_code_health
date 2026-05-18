class Example
  def shallow
    begin
      do_thing
    rescue StandardError
      log
    end
  end

  def deep
    if cond_a
      if cond_b
        if cond_c
          do_thing
        end
      end
    end
  end
end
