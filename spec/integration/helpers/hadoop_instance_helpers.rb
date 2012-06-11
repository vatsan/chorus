def create_valid_hadoop_instance(params = {})
  name = params[:name] || "hadoop_instance#{Time.now.to_i}"
  visit("#/instances")
  wait_until { current_route == "/instances" && page.has_selector?("button[data-dialog=InstancesNew]") }
  click_button "Add instance"
  within("#facebox") do
    choose("register_existing_hadoop")
    wait_until { find("input[name=name]").visible? }
    wait_until { find("textarea[name=description]").visible? }
    wait_until { find("input[name=host]").visible? }
    wait_until { find("input[name=port]").visible? }
    wait_until { find("input.username").visible? }
    wait_until { find("input.group_list").visible? }

    fill_in 'name', :with => name
    fill_in 'description', :with => "hadoop instance"
    fill_in 'host', :with => "gillette.sf.pivotallabs.com"
    fill_in 'port', :with => "8020"
    fill_in 'username', :with => "hadoop"
    fill_in 'groupList', :with => "hadoop"
    find(".submit").click
  end
  wait_until { current_route == "/instances" }
  wait_until { find('.instance_list').has_content?(name) }
  sleep(3)
end

def edit_hadoop_instance(params={})

  # assigning parameters to the different fields
  name = params[:name] || "hadoop_instance#{Time.now.to_i}"
  description = params[:description] || "Hadoop edit instance change description"
  host = params[:host] || "gillette.sf.pivotallabs.com"
  host = params[:port] || "8020"
  port = params[:username] || "hadoop"
  group = params[:group] || "hadoop"

  click_link "Edit Instance"

  wait_until { find("input[name=name]").visible? }
  wait_until { find("textarea[name=description]").visible? }
  wait_until { find("input[name=host]").visible? }
  wait_until { find("input[name=port]").visible? }
  wait_until { find("input.username").visible? }
  wait_until { find("input.group_list").visible? }


  within("#facebox") do
      fill_in 'name', :with => name
      fill_in 'description', :with => ""
      fill_in 'host', :with => "gillette.sf.pivotallabs.com"
      fill_in 'port', :with => "8020"
      fill_in 'username', :with => "hadoop"
      fill_in 'groupList', :with => "hadoop"
      click_button "Save Configuration"
    end
    wait_until { current_route == "/instances" }
    wait_until { find('.instance_list').has_content?(name) }
    sleep(2)
end

