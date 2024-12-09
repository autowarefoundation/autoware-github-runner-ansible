# autoware-github-runner-ansible

## Installation steps

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

#### Docker setup

```bash
ansible-playbook autoware.github_runner.docker_setup --ask-become-pass

# Restart to apply post-installation changes
sudo reboot
```

#### Runner setup

```bash
export PERSONAL_ACCESS_TOKEN=<your_personal_access_token>

ansible-playbook autoware.github_runner.runner_setup --ask-become-pass
```
