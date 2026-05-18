class ReportsController < ApplicationController
  before_action :load_report, only: [:show, :download]

  def index
    @reports = Report.all
  end

  def show
  end

  def download
    send_data @report.to_csv
  end

  private

  def load_report
    @report = Report.find(params[:id])
  end

  def report_params
    params.require(:report).permit(:title)
  end
end
