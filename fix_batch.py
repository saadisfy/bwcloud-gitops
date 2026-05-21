import re

with open('apps/alloy/noctua/templates/alloy-configmap.yaml', 'r') as f:
    content = f.read()

# Add send_batch_max_size = 10000 after send_batch_size = 8192
content = content.replace('send_batch_size = 8192', 'send_batch_size = 8192\n        send_batch_max_size = 10000')

with open('apps/alloy/noctua/templates/alloy-configmap.yaml', 'w') as f:
    f.write(content)

with open('apps/alloy/config.alloy', 'r') as f:
    content2 = f.read()

content2 = content2.replace('send_batch_size = 8192', 'send_batch_size = 8192\n    send_batch_max_size = 10000')

with open('apps/alloy/config.alloy', 'w') as f:
    f.write(content2)

print("Fixed batch size!")
