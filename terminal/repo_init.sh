#!/bin/bash
# sudo ln -s /Users/henry/Drive/Projects/GitHub/terminal/repo_init.sh /usr/local/bin/repo_init

# Set default values for parameters
repository_name=${1:-$(basename "$(pwd)")}
github_user=${2:-"wpwebs"}

# Retrieve credentials and keys from 1Password
github_username=$(op read "op://dev/github_${github_user}/username") || { echo "Failed to retrieve GitHub username from 1Password"; exit 1; }
app_token=$(op read "op://dev/github_${github_user}/admin_token") || { echo "Failed to retrieve App Token from 1Password"; exit 1; }

# Handling SSH key based on username
if [ "$github_username" == "thexglobal" ]; then
    ssh_key_path="op://dev/id_ssh/private_key"
    remote_url="git@thexgithub:${github_username}/${repository_name}.git"
elif [ "$github_username" == "wpwebs" ]; then
    ssh_key_path="op://dev/wpwebs/private key"
    remote_url="git@wpwebs:${github_username}/${repository_name}.git"
elif [ "$github_username" == "thesimonus" ]; then
    ssh_key_path="op://dev/thesimonus/private key"
    remote_url="git@thesimonus:${github_username}/${repository_name}.git"
else
    ssh_key_path="op:/dev/id_henry/private key"
    remote_url="git@henrygithub:${github_username}/${repository_name}.git"
fi

op read "$ssh_key_path" > /tmp/my_ssh_key || { echo "Failed to retrieve SSH key from 1Password"; exit 1; }

# Start the ssh-agent and add key
eval "$(ssh-agent -s)"
chmod 600 /tmp/my_ssh_key
ssh-add /tmp/my_ssh_key || { echo "Failed to add SSH key to the ssh-agent"; rm /tmp/my_ssh_key; exit 1; }
rm /tmp/my_ssh_key

# Create a new repository on GitHub
echo "Creating repository $repository_name on GitHub..."
response=$(curl -s -w "%{http_code}" -o /dev/null -X POST -H "Authorization: token $app_token" -H "Content-Type: application/json" -d "{\"name\":\"$repository_name\"}" https://api.github.com/user/repos)
if [ "$response" -ne 201 ]; then
    echo "Failed to create repository on GitHub: HTTP status code $response"
    exit 1
else
    echo "Repository $repository_name created successfully on GitHub."
fi

# Initialize and prepare local repository
rm -rf .git
git init || exit 1
git add . || exit 1
git commit -m "Initial repository" || exit 1

# Set remote and push changes
git remote add origin $remote_url || exit 1
echo "Pushing changes to GitHub..."
git push -u origin main || exit 1

echo "Repository git@github.com:${github_username}/${repository_name}.git was created successfully."

# Add collaborators if not henrysimonfamily
if [ "$github_username" != "henrysimonfamily" ]; then
    collaborator_username="henrysimonfamily"
    permission="push"
    echo "Adding collaborator $collaborator_username to the repository $remote_url ..."
    collaborator_response=$(curl -s -w "%{http_code}" -o /dev/null -X PUT -H "Authorization: token $app_token" -H "Content-Type: application/json" -d "{\"permission\": \"$permission\"}" https://api.github.com/repos/${github_username}/${repository_name}/collaborators/${collaborator_username})
    if [ "$collaborator_response" -ne 201 ]; then
        echo "Failed to add collaborator: HTTP status code $collaborator_response"
        exit 1
    else
        echo "Collaborator $collaborator_username added successfully."
    fi
fi
