module JidGenerator
  def jid
    SecureRandom.hex 12
  end
end
