.PHONY: clean gen
clean:
	rm -r Chart.yaml charts/ nodes/ templates/
	rm kubeconfig secrets.encrypted.yaml secrets.yaml talm.key talosconfig talosconfig.encrypted

gen:
	talm init --preset cozystack --name cozyaws
