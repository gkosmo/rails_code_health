class OrdersController < ApplicationController
  def create
    @order = Order.new(order_params)
    @order.calculate_total
    @order.charge!
    redirect_to @order
  end
end
