defmodule NervesHubWWWWeb.OrgUserView do
  use NervesHubWWWWeb, :view

  defmodule DateTimeFormat do
    @months %{1 => "Jan", 2 => "Feb", 3 => "Mar", 4 => "Apr",
      5 => "May", 6 => "Jun", 7 => "Jul", 8 => "Aug",
      9 => "Sep", 10 => "Oct", 11 => "Nov", 12 => "Dec"}
    
    def format(timestamp) do
      '#{@months[timestamp.month]} #{timestamp.day}, #{timestamp.year}'
    end
  end
end
