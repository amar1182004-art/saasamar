module Control
  module V1
    class BaseController < ApplicationController
      include ControlPlaneAuthentication
    end
  end
end
