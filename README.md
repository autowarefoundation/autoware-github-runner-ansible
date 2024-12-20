# autoware-github-runner-ansible

## Installation

### Install ansible

```bash
sudo apt update
sudo apt dist-upgrade -y

# Remove apt installed ansible (In Ubuntu 22.04, ansible the version is old)
sudo apt-get purge ansible

# Install pipx
sudo apt-get -y install pipx

# Add pipx to the system PATH
python3 -m pipx ensurepath

# Install ansible
pipx install --include-deps --force ansible
```

### Install ansible collections

```bash
ansible-galaxy install -f -r requirements.yaml
```

### Playbooks

#### Install useful apps

```bash
ansible-playbook autoware.github_runner.useful_apps --ask-become-pass
```

#### Docker setup

```bash
ansible-playbook autoware.github_runner.docker_setup --ask-become-pass

# Restart to apply post-installation changes
sudo reboot
```

#### Runner setup

- 🔴 Modify the PAT according to <https://github.com/MonolithProjects/ansible-github_actions_runner?tab=readme-ov-file#requirements> .
- 🔴 Modify the runner name.
- 🔴 Modify the GitHub account.

```bash
export PERSONAL_ACCESS_TOKEN=<your_personal_access_token>

ansible-playbook autoware.github_runner.runner_setup --ask-become-pass  --extra-vars "runner_name=ovh-runner-01 reinstall_runner=true github_account=xmfcx"
```

Set up the clean-up script.

```bash
ansible-playbook autoware.github_runner.runner_configuration --ask-become-pass

# Restart and check if everything is working
sudo reboot
```
